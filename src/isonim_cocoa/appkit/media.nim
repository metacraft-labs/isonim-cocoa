## Web, Media & Maps wrappers — WKWebView, AVPlayer, MKMapView.
##
## WKWebView — embedded web browser (WebKit framework).
## AVPlayer — audio/video playback (AVFoundation framework).
## MKMapView — interactive maps with annotations (MapKit framework).

import isonim_cocoa/objc_runtime
import isonim_cocoa/foundation
import isonim_cocoa/appkit/views

{.passL: "-framework WebKit -framework AVFoundation -framework MapKit".}

# ObjC helper compiled separately (needs ObjC mode for WebKit/MapKit types)
{.compile: currentSourcePath()[0..^(len("media.nim") + 1)] & "media_helper.m".}

# C-callable helpers from media_helper.m
proc nim_create_wkwebview(width, height: cint): Id {.importc, cdecl.}
proc nim_wkwebview_load_html(webView, htmlString, baseURLString: Id) {.importc, cdecl.}
proc nim_wkwebview_load_url(webView, urlString: Id) {.importc, cdecl.}
proc nim_wkwebview_eval_js(webView, jsCode: Id) {.importc, cdecl.}
proc nim_create_mkmapview(): Id {.importc, cdecl.}
proc nim_mapview_set_center(mapView: Id; lat, lon: cdouble) {.importc, cdecl.}
proc nim_mapview_center_lat(mapView: Id): cdouble {.importc, cdecl.}
proc nim_mapview_center_lon(mapView: Id): cdouble {.importc, cdecl.}
proc nim_mapview_add_annotation(mapView: Id; lat, lon: cdouble; titleString: Id) {.importc, cdecl.}
proc nim_mapview_annotation_count(mapView: Id): clong {.importc, cdecl.}
proc nim_mapview_remove_all_annotations(mapView: Id) {.importc, cdecl.}

# ===========================================================================
# WKWebView
# ===========================================================================

proc newWKWebView*(width, height: int): Id =
  ## Create a WKWebView with the given dimensions.
  nim_create_wkwebview(cint(width), cint(height))

proc webViewLoadHTML*(wv: Id; html: string; baseURL: string = "") =
  ## Load HTML content into a WKWebView.
  let nsHTML = toNSString(html)
  let nsBase = if baseURL.len > 0: toNSString(baseURL) else: NilId
  nim_wkwebview_load_html(wv, nsHTML, nsBase)
  release(nsHTML)
  if not nsBase.isNil:
    release(nsBase)

proc webViewLoadURL*(wv: Id; urlStr: string) =
  ## Load a URL in a WKWebView.
  let nsURL = toNSString(urlStr)
  nim_wkwebview_load_url(wv, nsURL)
  release(nsURL)

proc webViewURL*(wv: Id): string =
  ## Get the current URL of the WKWebView as a string.
  let url = msgSend(wv, sel("URL"))
  if url.isNil:
    return ""
  toNimString(msgSend(url, sel("absoluteString")))

proc webViewIsLoading*(wv: Id): bool =
  ## Check if the WKWebView is currently loading content.
  msgSendBool(wv, sel("isLoading"))

proc webViewGoBack*(wv: Id) =
  ## Navigate back in the WKWebView history.
  discard msgSend(wv, sel("goBack"))

proc webViewGoForward*(wv: Id) =
  ## Navigate forward in the WKWebView history.
  discard msgSend(wv, sel("goForward"))

proc webViewReload*(wv: Id) =
  ## Reload the current page in the WKWebView.
  discard msgSend(wv, sel("reload"))

proc webViewEvalJS*(wv: Id; jsCode: string; callback: proc(result: string) = nil) =
  ## Evaluate JavaScript in the WKWebView. The callback parameter is
  ## reserved for future use (ObjC block bridging needed for async result).
  ## Currently fires the eval without a completion handler.
  let nsCode = toNSString(jsCode)
  nim_wkwebview_eval_js(wv, nsCode)
  release(nsCode)

# ===========================================================================
# AVPlayer
# ===========================================================================

proc newAVPlayer*(): Id =
  ## Create an empty AVPlayer.
  allocInit("AVPlayer")

proc avPlayerSetURL*(p: Id; urlStr: string) =
  ## Set the player item to the given URL.
  let nsURLStr = toNSString(urlStr)
  let url = msgSend(Id(cls("NSURL")), sel("URLWithString:"), nsURLStr)
  let item = msgSend(Id(cls("AVPlayerItem")), sel("playerItemWithURL:"), url)
  msgSendVoid(p, sel("replaceCurrentItemWithPlayerItem:"), item)
  release(nsURLStr)

proc avPlayerPlay*(p: Id) =
  ## Start playback.
  msgSendVoid(p, sel("play"))

proc avPlayerPause*(p: Id) =
  ## Pause playback.
  msgSendVoid(p, sel("pause"))

proc avPlayerRate*(p: Id): cdouble =
  ## Get the current playback rate. 0 = paused, 1 = normal speed.
  msgSendFloat(p, sel("rate"))

proc avPlayerSetMuted*(p: Id; muted: bool) =
  ## Set the muted state of the player.
  msgSendVoidBool(p, sel("setMuted:"), muted)

proc avPlayerIsMuted*(p: Id): bool =
  ## Check if the player is muted.
  msgSendBool(p, sel("isMuted"))

proc avPlayerActionAtItemEnd*(p: Id): int =
  ## Get the action at item end. 0=none, 1=advance, 2=pause.
  int(msgSendInt(p, sel("actionAtItemEnd")))

proc avPlayerSetActionAtItemEnd*(p: Id; action: int) =
  ## Set the action at item end. 0=none (loop), 1=advance, 2=pause.
  msgSendVoid(p, sel("setActionAtItemEnd:"), clong(action))

# ===========================================================================
# MKMapView
# ===========================================================================

proc newMKMapView*(): Id =
  ## Create an MKMapView.
  nim_create_mkmapview()

proc mapViewSetCenter*(mv: Id; lat, lon: cdouble) =
  ## Set the center coordinate and a default span.
  nim_mapview_set_center(mv, lat, lon)

proc mapViewCenterLat*(mv: Id): cdouble =
  ## Get the latitude of the map center.
  nim_mapview_center_lat(mv)

proc mapViewCenterLon*(mv: Id): cdouble =
  ## Get the longitude of the map center.
  nim_mapview_center_lon(mv)

proc mapViewSetMapType*(mv: Id; mapType: int) =
  ## Set the map type: 0=standard, 1=satellite, 2=hybrid.
  msgSendVoid(mv, sel("setMapType:"), clong(mapType))

proc mapViewMapType*(mv: Id): int =
  ## Get the current map type.
  int(msgSendUint(mv, sel("mapType")))

proc mapViewAddAnnotation*(mv: Id; lat, lon: cdouble; title: string) =
  ## Add a point annotation at the given coordinates with a title.
  let nsTitle = toNSString(title)
  nim_mapview_add_annotation(mv, lat, lon, nsTitle)
  release(nsTitle)

proc mapViewAnnotationCount*(mv: Id): int =
  ## Return the number of annotations on the map.
  int(nim_mapview_annotation_count(mv))

proc mapViewRemoveAllAnnotations*(mv: Id) =
  ## Remove all annotations from the map.
  nim_mapview_remove_all_annotations(mv)
