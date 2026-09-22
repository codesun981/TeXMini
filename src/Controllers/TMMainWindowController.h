#import <Cocoa/Cocoa.h>
#import "TMDocument.h"

NS_ASSUME_NONNULL_BEGIN

@interface TMMainWindowController : NSWindowController <NSWindowDelegate>

@property (nonatomic, strong) TMDocument *documentModel;

- (instancetype)initWithDocument:(TMDocument *)document;
- (void)newDocumentAction:(nullable id)sender;
- (void)openDocumentAtURL:(NSURL *)url;
- (void)compileCurrentDocument;
- (void)saveCurrentDocument;
- (void)forwardSyncToPDF;
- (void)toggleLogDrawer;
- (void)toggleOutlineSidebar;
- (void)zoomIn;
- (void)zoomOut;

@end

NS_ASSUME_NONNULL_END
