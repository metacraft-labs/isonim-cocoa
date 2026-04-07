/* media_helper.m — ObjC helpers for WKWebView, AVPlayer, MKMapView.
 *
 * These functions require Objective-C compilation because they use
 * WebKit/AVFoundation/MapKit classes and struct types (MKCoordinateRegion).
 */

#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MapKit/MapKit.h>

/* ---- WKWebView ---- */

id nim_create_wkwebview(int width, int height) {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKWebView *wv = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, width, height)
                                       configuration:config];
    [config release];
    return (id)wv;
}

void nim_wkwebview_load_html(id webView, id htmlString, id baseURLString) {
    WKWebView *wv = (WKWebView *)webView;
    NSURL *baseURL = nil;
    if (baseURLString != nil) {
        NSString *urlStr = (NSString *)baseURLString;
        if ([urlStr length] > 0) {
            baseURL = [NSURL URLWithString:urlStr];
        }
    }
    [wv loadHTMLString:(NSString *)htmlString baseURL:baseURL];
}

void nim_wkwebview_load_url(id webView, id urlString) {
    WKWebView *wv = (WKWebView *)webView;
    NSURL *url = [NSURL URLWithString:(NSString *)urlString];
    if (url) {
        NSURLRequest *req = [NSURLRequest requestWithURL:url];
        [wv loadRequest:req];
    }
}

void nim_wkwebview_eval_js(id webView, id jsCode) {
    WKWebView *wv = (WKWebView *)webView;
    [wv evaluateJavaScript:(NSString *)jsCode completionHandler:nil];
}

/* ---- MKMapView ---- */

id nim_create_mkmapview(void) {
    MKMapView *mv = [[MKMapView alloc] initWithFrame:NSMakeRect(0, 0, 300, 300)];
    return (id)mv;
}

void nim_mapview_set_center(id mapView, double lat, double lon) {
    MKMapView *mv = (MKMapView *)mapView;
    CLLocationCoordinate2D center = {lat, lon};
    MKCoordinateSpan span = {0.05, 0.05};
    MKCoordinateRegion region = {center, span};
    [mv setRegion:region animated:NO];
}

double nim_mapview_center_lat(id mapView) {
    MKMapView *mv = (MKMapView *)mapView;
    return mv.centerCoordinate.latitude;
}

double nim_mapview_center_lon(id mapView) {
    MKMapView *mv = (MKMapView *)mapView;
    return mv.centerCoordinate.longitude;
}

void nim_mapview_add_annotation(id mapView, double lat, double lon, id titleString) {
    MKMapView *mv = (MKMapView *)mapView;
    MKPointAnnotation *ann = [[MKPointAnnotation alloc] init];
    ann.coordinate = (CLLocationCoordinate2D){lat, lon};
    if (titleString != nil) {
        ann.title = (NSString *)titleString;
    }
    [mv addAnnotation:ann];
    [ann release];
}

long nim_mapview_annotation_count(id mapView) {
    MKMapView *mv = (MKMapView *)mapView;
    return (long)[[mv annotations] count];
}

void nim_mapview_remove_all_annotations(id mapView) {
    MKMapView *mv = (MKMapView *)mapView;
    [mv removeAnnotations:[mv annotations]];
}
