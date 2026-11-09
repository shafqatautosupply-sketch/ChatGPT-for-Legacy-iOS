#import <Foundation/Foundation.h>

extern NSString * const AGHTTPErrorDomain;

/// Synchronous HTTPS client on top of the bundled libcurl 7.33 / OpenSSL 1.0.2
/// (iOS 6's NSURLConnection cannot negotiate TLS 1.2, which api endpoints need).
///
/// Compared with the original shim:
///  * certificate verification is ON, using the bundled cacert.pem
///    (Resources/cacert.pem). Turning it off is an explicit setting
///    (`ag_insecure_tls`), never a silent default;
///  * connect/transfer timeouts are enforced, and `isCancelled` aborts a
///    transfer in flight (so Stop works while waiting for the model);
///  * redirects are not followed (the API key header would be re-sent to the
///    redirect target);
///  * gzip is accepted, responses are capped, and errors carry curl's text.
/// Only options that exist in libcurl 7.33 are used (the bundled headers are 7.58).
@interface AGHTTPClient : NSObject

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                 returningResponse:(NSURLResponse **)response
                             error:(NSError **)error
                       isCancelled:(BOOL (^)(void))cancelled;

+ (BOOL)isInsecureTLSEnabled;
+ (void)setInsecureTLSEnabled:(BOOL)enabled;

@end
