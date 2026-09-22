#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol TMEditorTextViewDelegate <NSTextViewDelegate>
@optional
- (void)editorTextViewDidChangeCursorPositionToLine:(NSInteger)line column:(NSInteger)column;
@end

@interface TMEditorTextView : NSTextView

@property (nonatomic, weak) id<TMEditorTextViewDelegate> editorDelegate;

- (void)setupEditor;
- (void)jumpToLine:(NSInteger)lineNumber column:(NSInteger)column;
- (void)rehighlightAll;

/// 以下动作作用于选区覆盖的整行，可撤销。
- (IBAction)toggleComment:(nullable id)sender;
- (IBAction)indentSelection:(nullable id)sender;
- (IBAction)outdentSelection:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
