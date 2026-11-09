#import <Foundation/Foundation.h>

/// Symlink-aware path confinement used by every agent tool.
///
/// Why not `stringByStandardizingPath` + `hasPrefix:`?
///  * it does not follow symlinks reliably, so a link inside the workspace that
///    points at "/" walks straight out of the jail;
///  * `hasPrefix:@"/var/mobile/Documents/SandBox"` also matches
///    ".../SandBox-evil", a sibling directory.
/// Here every component is lstat()ed and links are resolved by hand, `..` is
/// folded only after resolution, and containment is checked on a "/" boundary.
@interface AGPathJail : NSObject

/// Canonical absolute path (symlinks of existing components resolved, `.`/`..`
/// folded). Components that do not exist yet are kept verbatim, so this also
/// works for files that are about to be created. Returns nil on symlink loops.
+ (NSString *)canonicalPath:(NSString *)path relativeTo:(NSString *)base;

/// YES if `canonical` equals `root` or lives below it (boundary-safe).
+ (BOOL)canonicalPath:(NSString *)canonical isWithinRoot:(NSString *)root;

/// YES if `canonical` lives inside any of the (already canonical) `roots`.
+ (BOOL)canonicalPath:(NSString *)canonical isWithinAnyRoot:(NSArray *)roots;

/// Canonicalises each path in `paths` (relative entries are ignored).
+ (NSArray *)canonicalRoots:(NSArray *)paths;

@end
