## MockURLProtocol — intercept all NSURLSession requests for testing.
##
## Registers a dynamic ObjC subclass of NSURLProtocol that intercepts
## HTTP(S) requests. Tests configure expected responses via `expect`,
## then verify requests were made via `verify`.
##
## Usage:
##   let mock = newMockNetwork()
##   mock.install()
##   mock.expect("GET", "/api/users", 200, """[{"name":"Zahary"}]""")
##   ... code that makes HTTP request ...
##   pumpRunLoop()
##   check mock.wasCalledOnce("GET", "/api/users")
##   mock.uninstall()

import std/[tables, strutils, sequtils]
import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation

{.passL: "-framework Foundation".}

type
  MockResponse* = object
    statusCode*: int
    headers*: Table[string, string]
    body*: string

  CapturedRequest* = object
    httpMethod*: string
    url*: string
    headers*: Table[string, string]
    body*: string

  MockExpectation = object
    httpMethod: string
    urlPattern: string  # substring match against URL
    response: MockResponse

  MockNetwork* = ref object
    expectations: seq[MockExpectation]
    capturedRequests*: seq[CapturedRequest]
    installed: bool
    defaultResponse: MockResponse

# Global singleton — ObjC callback methods need access
var activeMock*: MockNetwork = nil

proc newMockNetwork*(): MockNetwork =
  MockNetwork(
    expectations: @[],
    capturedRequests: @[],
    installed: false,
    defaultResponse: MockResponse(
      statusCode: 404,
      headers: {"Content-Type": "text/plain"}.toTable,
      body: "Mock: no expectation matched"
    )
  )

proc expect*(mock: MockNetwork; httpMethod, urlPattern: string;
             statusCode: int = 200; body: string = "";
             contentType: string = "application/json") =
  ## Register an expected request and its canned response.
  mock.expectations.add(MockExpectation(
    httpMethod: httpMethod.toUpperAscii,
    urlPattern: urlPattern,
    response: MockResponse(
      statusCode: statusCode,
      headers: {"Content-Type": contentType}.toTable,
      body: body
    )
  ))

proc findResponse(mock: MockNetwork; httpMethod, url: string): MockResponse =
  for exp in mock.expectations:
    if exp.httpMethod == httpMethod.toUpperAscii and url.contains(exp.urlPattern):
      return exp.response
  return mock.defaultResponse

proc wasCalled*(mock: MockNetwork; httpMethod, urlPattern: string): int =
  ## Return the number of times a matching request was captured.
  var count = 0
  for req in mock.capturedRequests:
    if req.httpMethod == httpMethod.toUpperAscii and req.url.contains(urlPattern):
      inc count
  count

proc wasCalledOnce*(mock: MockNetwork; httpMethod, urlPattern: string): bool =
  mock.wasCalled(httpMethod, urlPattern) == 1

proc lastRequest*(mock: MockNetwork; httpMethod, urlPattern: string): CapturedRequest =
  ## Return the last captured request matching the pattern.
  for i in countdown(mock.capturedRequests.len - 1, 0):
    let req = mock.capturedRequests[i]
    if req.httpMethod == httpMethod.toUpperAscii and req.url.contains(urlPattern):
      return req
  CapturedRequest()

proc reset*(mock: MockNetwork) =
  ## Clear all expectations and captured requests.
  mock.expectations.setLen(0)
  mock.capturedRequests.setLen(0)

# ---------------------------------------------------------------------------
# NSURLProtocol dynamic subclass
# ---------------------------------------------------------------------------

var mockProtocolClass: Class
var mockProtocolRegistered = false

# +canInitWithRequest: — return YES for http/https requests
proc canInitWithRequest(self: Id; cmd: Sel; request: Id): bool {.cdecl.} =
  if activeMock == nil:
    return false
  # Check if the request has our marker property to avoid recursion
  let markerKey = toNSString("NimMockHandled")
  let marker = msgSend(Id(cls("NSURLProtocol")), sel("propertyForKey:inRequest:"),
                        markerKey, request)
  release(markerKey)
  if not marker.isNil:
    return false
  # Accept all HTTP(S) requests
  let url = msgSend(request, sel("URL"))
  if url.isNil:
    return false
  let scheme = toNimString(msgSend(url, sel("scheme")))
  result = scheme == "http" or scheme == "https"

# +canonicalRequestForRequest: — return the request unchanged
proc canonicalRequest(self: Id; cmd: Sel; request: Id): Id {.cdecl.} =
  request

# -startLoading — deliver canned response
proc startLoading(self: Id; cmd: Sel) {.cdecl.} =
  if activeMock == nil:
    return

  let request = msgSend(self, sel("request"))
  let url = msgSend(request, sel("URL"))
  let urlString = toNimString(msgSend(url, sel("absoluteString")))
  let httpMethod = toNimString(msgSend(request, sel("HTTPMethod")))

  # Capture the request
  activeMock.capturedRequests.add(CapturedRequest(
    httpMethod: httpMethod,
    url: urlString,
    headers: initTable[string, string](),
    body: ""
  ))

  # Find matching response
  let resp = activeMock.findResponse(httpMethod, urlString)

  # Create NSHTTPURLResponse
  let nsUrl = msgSend(request, sel("URL"))
  let statusCode = clong(resp.statusCode)
  let headerDict = newNSMutableDictionary()
  for k, v in resp.headers:
    let nsKey = toNSString(k)
    let nsVal = toNSString(v)
    nsDictSetObject(headerDict, nsVal, nsKey)
    release(nsKey)
    release(nsVal)

  # Create response object via emit (complex init signature)
  let client = msgSend(self, sel("client"))
  {.emit: """
  NSHTTPURLResponse *httpResp = [[NSHTTPURLResponse alloc]
    initWithURL:`nsUrl` statusCode:`statusCode`
    HTTPVersion:@"HTTP/1.1" headerFields:`headerDict`];

  // Deliver response
  ((void(*)(id, SEL, id, NSInteger, id))objc_msgSend)(
    `client`, sel_registerName("URLProtocol:didReceiveResponse:cacheStoragePolicy:"),
    `self`, (NSInteger)httpResp, (NSInteger)0);

  // Deliver body data
  NSData *bodyData = [@(`resp`.body.p->data) dataUsingEncoding:NSUTF8StringEncoding];
  """.}

  # Deliver body data and finish via emit
  {.emit: """
  ((void(*)(id, SEL, id, id))objc_msgSend)(
    `client`, sel_registerName("URLProtocol:didLoadData:"),
    `self`, bodyData);

  ((void(*)(id, SEL, id))objc_msgSend)(
    `client`, sel_registerName("URLProtocolDidFinishLoading:"),
    `self`);

  [httpResp release];
  """.}

  release(headerDict)

# -stopLoading — no-op
proc stopLoading(self: Id; cmd: Sel) {.cdecl.} =
  discard

proc ensureMockProtocolClass() =
  if mockProtocolClass.isNil:
    mockProtocolClass = objc_allocateClassPair(
      cls("NSURLProtocol"), "NimMockURLProtocol".cstring)

    # Class methods (on metaclass)
    let metaclass = object_getClass(Id(mockProtocolClass))
    discard class_addMethod(metaclass, sel("canInitWithRequest:"),
      cast[Imp](canInitWithRequest), "B@:@".cstring)
    discard class_addMethod(metaclass, sel("canonicalRequestForRequest:"),
      cast[Imp](canonicalRequest), "@@:@".cstring)

    # Instance methods
    discard class_addMethod(mockProtocolClass, sel("startLoading"),
      cast[Imp](startLoading), "v@:".cstring)
    discard class_addMethod(mockProtocolClass, sel("stopLoading"),
      cast[Imp](stopLoading), "v@:".cstring)

    objc_registerClassPair(mockProtocolClass)

proc install*(mock: MockNetwork) =
  ## Register the mock protocol to intercept all HTTP(S) requests.
  ensureMockProtocolClass()
  activeMock = mock
  mock.installed = true
  msgSendVoid(Id(cls("NSURLProtocol")), sel("registerClass:"), Id(mockProtocolClass))

proc uninstall*(mock: MockNetwork) =
  ## Unregister the mock protocol.
  if mock.installed:
    msgSendVoid(Id(cls("NSURLProtocol")), sel("unregisterClass:"), Id(mockProtocolClass))
    mock.installed = false
    if activeMock == mock:
      activeMock = nil
