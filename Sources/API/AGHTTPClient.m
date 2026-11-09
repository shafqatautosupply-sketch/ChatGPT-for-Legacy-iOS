#import "AGHTTPClient.h"

#include "curl.h"
#include "easy.h"
#include <string.h>
#include <stdlib.h>
#include <strings.h>

NSString * const AGHTTPErrorDomain = @"AGHTTPErrorDomain";
static NSString * const AGInsecureTLSKey = @"ag_insecure_tls";
static const size_t AGMaxResponseBytes = 16 * 1024 * 1024;

typedef struct {
	char *memory;
	size_t size;
	BOOL overflow;
	char retryAfter[32];
	BOOL (^cancelled)(void);
} AGTransfer;

static size_t AGWriteCallback(void *ptr, size_t size, size_t nmemb, void *userdata) {
	AGTransfer *t = (AGTransfer *)userdata;
	size_t real = size * nmemb;
	if (t->size + real > AGMaxResponseBytes) { t->overflow = YES; return 0; }
	char *grown = (char *)realloc(t->memory, t->size + real + 1);
	if (grown == NULL) return 0; // old block stays owned by `t` and is freed by the caller
	t->memory = grown;
	memcpy(t->memory + t->size, ptr, real);
	t->size += real;
	t->memory[t->size] = 0;
	return real;
}

static size_t AGHeaderCallback(char *buffer, size_t size, size_t nitems, void *userdata) {
	AGTransfer *t = (AGTransfer *)userdata;
	size_t real = size * nitems;
	static const char name[] = "retry-after:";
	if (real > sizeof(name) - 1 && strncasecmp(buffer, name, sizeof(name) - 1) == 0) {
		size_t i = sizeof(name) - 1, n = 0;
		while (i < real && (buffer[i] == ' ' || buffer[i] == '\t')) i++;
		while (i < real && n < sizeof(t->retryAfter) - 1 && buffer[i] != '\r' && buffer[i] != '\n') t->retryAfter[n++] = buffer[i++];
		t->retryAfter[n] = '\0';
	}
	return real;
}

// libcurl calls this at least once a second, more often while data moves.
static int AGProgressCallback(void *userdata, double dltotal, double dlnow, double ultotal, double ulnow) {
	AGTransfer *t = (AGTransfer *)userdata;
	return (t->cancelled != NULL && t->cancelled()) ? 1 : 0;
}

@implementation AGHTTPClient

+ (BOOL)isInsecureTLSEnabled {
	return [[NSUserDefaults standardUserDefaults] boolForKey:AGInsecureTLSKey];
}
+ (void)setInsecureTLSEnabled:(BOOL)enabled {
	[[NSUserDefaults standardUserDefaults] setBool:enabled forKey:AGInsecureTLSKey];
}

+ (NSError *)errorForCurlCode:(int)code tls:(BOOL)verifying overflow:(BOOL)overflow {
	NSString *text = [NSString stringWithUTF8String:curl_easy_strerror((CURLcode)code)] ?: @"Network error";
	NSString *hint = @"";
	switch (code) {
		case 60: case 51: case 58: case 59: case 77: case 83:
			hint = verifying
				? @" The server certificate could not be verified. Check the device date and time first (a wrong clock breaks certificate checks). If it is correct, refresh Resources/cacert.pem, or as a last resort enable Settings > Agent > Insecure TLS."
				: @"";
			break;
		case 28: hint = @" The server did not answer in time."; break;
		case 6:  hint = @" Could not resolve the host name (no internet?)."; break;
		case 7:  hint = @" Could not connect to the server."; break;
		case 42: hint = @""; break;
		case 23: if (overflow) hint = @" Response exceeded the 16 MB safety limit."; break;
	}
	NSString *message = [NSString stringWithFormat:@"%@ (curl error %d).%@", text, code, hint];
	return [NSError errorWithDomain:AGHTTPErrorDomain code:code userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
}

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                 returningResponse:(NSURLResponse **)responsep
                             error:(NSError **)errorp
                       isCancelled:(BOOL (^)(void))cancelled {
	BOOL isHTTPS = [[[[request URL] scheme] lowercaseString] isEqualToString:@"https"];
	BOOL insecure = [self isInsecureTLSEnabled];
	NSString *caPath = nil;
	if (isHTTPS && !insecure) {
		caPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"ag_ca_bundle_path"]; // optional override, no rebuild needed
		if ([caPath length] == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:caPath]) {
			caPath = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
		}
		if (caPath == nil) {
			if (errorp) *errorp = [NSError errorWithDomain:AGHTTPErrorDomain code:-1 userInfo:[NSDictionary dictionaryWithObject:
				@"cacert.pem is missing from the app bundle, so HTTPS certificates cannot be verified. Rebuild with Resources/cacert.pem, or enable Settings > Agent > Insecure TLS." forKey:NSLocalizedDescriptionKey]];
			return nil;
		}
	}

	AGTransfer transfer;
	memset(&transfer, 0, sizeof(transfer));
	transfer.cancelled = cancelled;

	CURL *curl = curl_easy_init();
	if (curl == NULL) {
		if (errorp) *errorp = [NSError errorWithDomain:AGHTTPErrorDomain code:1 userInfo:[NSDictionary dictionaryWithObject:@"Could not initialise the network library." forKey:NSLocalizedDescriptionKey]];
		return nil;
	}

	curl_easy_setopt(curl, CURLOPT_URL, [[[request URL] absoluteString] UTF8String]);
	curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
	curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);
	curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 20L);
	NSTimeInterval timeout = [request timeoutInterval];
	curl_easy_setopt(curl, CURLOPT_TIMEOUT, (long)((timeout > 1.0) ? timeout : 120.0));
	curl_easy_setopt(curl, CURLOPT_ENCODING, ""); // all encodings libcurl was built with (gzip via the bundled libz)

	if (!isHTTPS) {
		// plain http: nothing to verify (the settings screen warns about sending a key this way)
	} else if (insecure) {
		curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
		curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
	} else {
		curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
		curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
		curl_easy_setopt(curl, CURLOPT_CAINFO, [caPath fileSystemRepresentation]);
	}

	NSString *method = [request HTTPMethod];
	NSData *body = [request HTTPBody];
	if ([method isEqualToString:@"POST"]) {
		curl_easy_setopt(curl, CURLOPT_POSTFIELDS, [body bytes]);
		curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)[body length]);
	} else if ([method isEqualToString:@"DELETE"]) {
		curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "DELETE");
	} else {
		curl_easy_setopt(curl, CURLOPT_HTTPGET, 1L);
	}

	struct curl_slist *headerList = NULL;
	NSDictionary *headers = [request allHTTPHeaderFields];
	for (NSString *key in headers) {
		headerList = curl_slist_append(headerList, [[NSString stringWithFormat:@"%@: %@", key, [headers objectForKey:key]] UTF8String]);
	}
	headerList = curl_slist_append(headerList, "Expect:"); // no 100-continue round trip for big bodies
	curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headerList);

	curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, AGWriteCallback);
	curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&transfer);
	curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, AGHeaderCallback);
	curl_easy_setopt(curl, CURLOPT_HEADERDATA, (void *)&transfer);
	curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
	curl_easy_setopt(curl, CURLOPT_PROGRESSFUNCTION, AGProgressCallback);
	curl_easy_setopt(curl, CURLOPT_PROGRESSDATA, (void *)&transfer);

	int result = (int)curl_easy_perform(curl);
	long statusCode = 0;
	curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &statusCode);
	curl_slist_free_all(headerList);
	curl_easy_cleanup(curl);

	NSData *data = nil;
	if (result == 0) {
		data = [NSData dataWithBytes:(transfer.memory ? transfer.memory : "") length:transfer.size];
		if (responsep != NULL) {
			NSMutableDictionary *fields = [NSMutableDictionary dictionary];
			if (transfer.retryAfter[0] != '\0') [fields setObject:[NSString stringWithUTF8String:transfer.retryAfter] forKey:@"Retry-After"];
			*responsep = [[[NSHTTPURLResponse alloc] initWithURL:[request URL] statusCode:(NSInteger)statusCode HTTPVersion:@"HTTP/1.1" headerFields:fields] autorelease];
		}
	} else if (errorp != NULL) {
		*errorp = [self errorForCurlCode:result tls:(isHTTPS && !insecure) overflow:transfer.overflow];
	}
	if (transfer.memory != NULL) free(transfer.memory);
	return data;
}

@end
