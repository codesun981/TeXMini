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

@end

NS_ASSUME_NONNULL_END
