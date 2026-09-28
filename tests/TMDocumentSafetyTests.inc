// Included by TMTests.m; only Foundation + TMDocument are needed.
#import <sys/stat.h>

static NSURL *tm_safetyDirectory(void) {
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
        [@"tm-document-safety-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
    return url;
}

TM_TEST(test_clean_preserves_user_index_styles) {
    NSURL *dir = tm_safetyDirectory();
    for (NSString *name in @[@"main.tex", @"main.ist", @"main.xdy", @"main.aux", @"main.idx", @"main.ind"]) {
        [@"source or generated" writeToURL:[dir URLByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    [TMDocument cleanAuxiliaryFilesForTeXFileURL:[dir URLByAppendingPathComponent:@"main.tex"]];
    for (NSString *name in @[@"main.tex", @"main.ist", @"main.xdy"]) {
        TM_ASSERT_TRUE([NSFileManager.defaultManager fileExistsAtPath:[dir URLByAppendingPathComponent:name].path]);
    }
    TM_ASSERT_TRUE(![NSFileManager.defaultManager fileExistsAtPath:[dir URLByAppendingPathComponent:@"main.aux"].path]);
    TM_ASSERT_TRUE(![NSFileManager.defaultManager fileExistsAtPath:[dir URLByAppendingPathComponent:@"main.idx"].path]);
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}

TM_TEST(test_document_declared_latin1_roundtrip_and_no_lossy_save) {
    NSURL *dir = tm_safetyDirectory(), *url = [dir URLByAppendingPathComponent:@"latin1.tex"];
    NSString *text = @"\\documentclass{article}\n\\usepackage[latin1]{inputenc}\nGrüße aus Köln\n";
    NSData *original = [text dataUsingEncoding:NSISOLatin1StringEncoding];
    [original writeToURL:url atomically:YES];
    TMDocument *doc = [TMDocument documentWithContentsOfURL:url error:nil];
    TM_ASSERT_EQ_STR(doc.content, text);
    TM_ASSERT_TRUE([doc saveCurrentFileWithError:nil]);
    TM_ASSERT_TRUE([[NSData dataWithContentsOfURL:url] isEqualToData:original]);
    doc.content = [text stringByAppendingString:@"中文"];
    doc.isDirty = YES;
    NSError *error = nil;
    TM_ASSERT_TRUE(![doc saveCurrentFileWithError:&error]);
    TM_ASSERT_EQ_INT(error.code, TMDocumentErrorUnrepresentableEncoding);
    TM_ASSERT_TRUE(doc.isDirty);
    TM_ASSERT_TRUE([[NSData dataWithContentsOfURL:url] isEqualToData:original]);
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}

TM_TEST(test_document_declared_gbk_roundtrip) {
    NSURL *dir = tm_safetyDirectory(), *url = [dir URLByAppendingPathComponent:@"gbk.tex"];
    NSStringEncoding gbk = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    NSString *text = @"% !TEX encoding = GBK\n\\documentclass{article}\n中文测试\n";
    NSData *original = [text dataUsingEncoding:gbk];
    [original writeToURL:url atomically:YES];
    TMDocument *doc = [TMDocument documentWithContentsOfURL:url error:nil];
    TM_ASSERT_EQ_STR(doc.content, text);
    TM_ASSERT_TRUE([doc saveCurrentFileWithError:nil]);
    TM_ASSERT_TRUE([[NSData dataWithContentsOfURL:url] isEqualToData:original]);
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}

TM_TEST(test_document_ambiguous_legacy_encoding_is_not_silently_latin1) {
    NSURL *dir = tm_safetyDirectory(), *url = [dir URLByAppendingPathComponent:@"unknown.tex"];
    const unsigned char gbk[] = {0xd6, 0xd0, 0xce, 0xc4, 0x0a};
    NSData *original = [NSData dataWithBytes:gbk length:sizeof(gbk)];
    [original writeToURL:url atomically:YES];
    NSError *error = nil;
    TMDocument *doc = [TMDocument documentWithContentsOfURL:url error:&error];
    TM_ASSERT_NIL(doc);
    TM_ASSERT_EQ_INT(error.code, TMDocumentErrorUnknownEncoding);
    TM_ASSERT_TRUE([[NSData dataWithContentsOfURL:url] isEqualToData:original]);
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}

TM_TEST(test_document_utf8_and_utf16_bom_roundtrip) {
    NSURL *dir = tm_safetyDirectory();
    NSString *text = @"\\documentclass{article}\n中文 résumé\n";
    for (NSNumber *value in @[@(NSUTF8StringEncoding), @(NSUTF16StringEncoding)]) {
        NSURL *url = [dir URLByAppendingPathComponent:[NSString stringWithFormat:@"unicode-%@.tex", value]];
        NSData *original = [text dataUsingEncoding:value.unsignedIntegerValue];
        [original writeToURL:url atomically:YES];
        TMDocument *doc = [TMDocument documentWithContentsOfURL:url error:nil];
        TM_ASSERT_EQ_STR(doc.content, text);
        TM_ASSERT_TRUE([doc saveCurrentFileWithError:nil]);
        TM_ASSERT_TRUE([[NSData dataWithContentsOfURL:url] isEqualToData:original]);
    }
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}

TM_TEST(test_document_unmarked_unicode_is_correct_or_explicitly_rejected) {
    NSURL *dir = tm_safetyDirectory(), *url = [dir URLByAppendingPathComponent:@"utf16.tex"];
    NSString *text = @"\\documentclass{article}\n\\begin{document}\n中文 résumé\n\\end{document}\n";
    NSData *original = [text dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    [original writeToURL:url atomically:YES];
    NSError *error = nil;
    TMDocument *doc = [TMDocument documentWithContentsOfURL:url error:&error];
    // Foundation 的无 BOM 检测因系统版本而异；不能可靠判断时宁可清楚报错。
    if (doc) {
        TM_ASSERT_EQ_STR(doc.content, text);
        TM_ASSERT_TRUE([doc saveCurrentFileWithError:nil]);
        TM_ASSERT_TRUE([[NSData dataWithContentsOfURL:url] isEqualToData:original]);
    } else {
        TM_ASSERT_EQ_INT(error.code, TMDocumentErrorUnknownEncoding);
    }
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}

TM_TEST(test_document_updated_encoding_declaration_converts_losslessly) {
    NSURL *dir = tm_safetyDirectory(), *url = [dir URLByAppendingPathComponent:@"main.tex"];
    NSString *oldText = @"% !TEX encoding = latin1\nGrüße\n";
    [[oldText dataUsingEncoding:NSISOLatin1StringEncoding] writeToURL:url atomically:YES];
    TMDocument *doc = [TMDocument documentWithContentsOfURL:url error:nil];
    doc.content = @"% !TEX encoding = UTF-8\nGrüße 中文\n";
    doc.isDirty = YES;
    TM_ASSERT_TRUE([doc saveCurrentFileWithError:nil]);
    TM_ASSERT_EQ_INT(doc.textEncoding, NSUTF8StringEncoding);
    TM_ASSERT_EQ_STR([TMDocument documentWithContentsOfURL:url error:nil].content, doc.content);
    NSData *saved = [NSData dataWithContentsOfURL:url];
    doc.content = @"% !TEX encoding = NOT-A-REAL-ENCODING\ntext\n";
    doc.isDirty = YES;
    NSError *error = nil;
    TM_ASSERT_TRUE(![doc saveCurrentFileWithError:&error]);
    TM_ASSERT_EQ_INT(error.code, TMDocumentErrorUnknownEncoding);
    TM_ASSERT_TRUE([[NSData dataWithContentsOfURL:url] isEqualToData:saved]);
    TM_ASSERT_TRUE(doc.isDirty);
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}

TM_TEST(test_document_detects_replacement_even_when_size_and_mtime_match) {
    NSURL *dir = tm_safetyDirectory(), *url = [dir URLByAppendingPathComponent:@"main.tex"];
    [@"OLD!" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    TMDocument *doc = [TMDocument documentWithContentsOfURL:url error:nil];
    NSDate *mtime = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil][NSFileModificationDate];
    [@"NEW!" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:mtime} ofItemAtPath:url.path error:nil];
    TM_ASSERT_TRUE([doc hasExternalChanges]);
    doc.content = @"LOCAL";
    doc.isDirty = YES;
    NSError *error = nil;
    TM_ASSERT_TRUE(![doc saveCurrentFileWithError:&error]);
    TM_ASSERT_EQ_INT(error.code, TMDocumentErrorExternalChange);
    TM_ASSERT_EQ_STR([NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil], @"NEW!");
    TM_ASSERT_TRUE(doc.isDirty);
    [doc acknowledgeExternalChanges];
    TM_ASSERT_TRUE(![doc hasExternalChanges]);
    TM_ASSERT_TRUE([doc saveCurrentFileWithError:nil]);
    TM_ASSERT_EQ_STR([NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil], @"LOCAL");
    TM_ASSERT_TRUE(![doc hasExternalChanges]);
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}

TM_TEST(test_document_detects_delete_and_allows_explicit_save_as) {
    NSURL *dir = tm_safetyDirectory(), *url = [dir URLByAppendingPathComponent:@"main.tex"];
    [@"Original" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    TMDocument *doc = [TMDocument documentWithContentsOfURL:url error:nil];
    [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    TM_ASSERT_TRUE([doc hasExternalChanges]);
    TM_ASSERT_TRUE(![doc saveCurrentFileWithError:nil]);
    NSURL *newURL = [dir URLByAppendingPathComponent:@"saved-as.tex"];
    TM_ASSERT_TRUE([doc saveToURL:newURL error:nil]);
    TM_ASSERT_TRUE(![doc hasExternalChanges]);
    TM_ASSERT_TRUE([doc.fileURL isEqual:newURL]);
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}

TM_TEST(test_document_accepts_only_the_disk_snapshot_shown_to_user) {
    NSURL *dir = tm_safetyDirectory(), *url = [dir URLByAppendingPathComponent:@"main.tex"];
    [@"BASE" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    TMDocument *local = [TMDocument documentWithContentsOfURL:url error:nil];
    local.content = @"LOCAL";
    [@"FIRST EXTERNAL" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    TMDocument *shown = [TMDocument documentWithContentsOfURL:url error:nil];
    [local acknowledgeDiskStateFromDocument:shown];
    TM_ASSERT_TRUE(![local hasExternalChanges]);
    TM_ASSERT_EQ_STR(local.content, @"LOCAL");
    [@"SECOND EXTERNAL" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [local acknowledgeDiskStateFromDocument:shown];
    TM_ASSERT_TRUE([local hasExternalChanges]);
    TM_ASSERT_TRUE(![local saveCurrentFileWithError:nil]);
    TM_ASSERT_EQ_STR([NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil], @"SECOND EXTERNAL");
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}

TM_TEST(test_document_detects_inplace_write_with_restored_mtime) {
    NSURL *dir = tm_safetyDirectory(), *url = [dir URLByAppendingPathComponent:@"main.tex"];
    [@"BASE" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    TMDocument *doc = [TMDocument documentWithContentsOfURL:url error:nil];
    NSDictionary *before = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:url.path];
    [handle writeData:[@"EDIT" dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
    [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:before[NSFileModificationDate]} ofItemAtPath:url.path error:nil];
    NSDictionary *after = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
    TM_ASSERT_EQ_INT([before[NSFileSystemFileNumber] unsignedLongLongValue], [after[NSFileSystemFileNumber] unsignedLongLongValue]);
    TM_ASSERT_TRUE([doc hasExternalChanges]);
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}

TM_TEST(test_document_encoding_examples_do_not_reinterpret_utf8_text) {
    NSURL *dir = tm_safetyDirectory();
    for (NSString *example in @[@"\\verb|\\usepackage[latin1]{inputenc}|",
                               @"\\begin{verbatim}\n\\usepackage[latin1]{inputenc}\n\\end{verbatim}",
                               @"% !TEX encoding = latin1"]) {
        NSURL *url = [dir URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *text = [NSString stringWithFormat:@"\\documentclass{article}\n\\begin{document}\nRésumé 中文\n%@\n\\end{document}\n", example];
        [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
        TMDocument *doc = [TMDocument documentWithContentsOfURL:url error:nil];
        TM_ASSERT_EQ_STR(doc.content, text);
        doc.content = [text stringByAppendingString:@"% café\n"];
        doc.isDirty = YES;
        TM_ASSERT_TRUE([doc saveCurrentFileWithError:nil]);
        TM_ASSERT_TRUE(!doc.isDirty);
        TM_ASSERT_EQ_INT(doc.textEncoding, NSUTF8StringEncoding);
        TM_ASSERT_EQ_STR([NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil], doc.content);
    }
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}

TM_TEST(test_document_only_real_top_level_preamble_inputenc_sets_encoding) {
    NSURL *dir = tm_safetyDirectory();
    for (NSString *example in @[@"\\newcommand{\\example}{\\usepackage[GBK]{inputenc}}",
                               @"\\newcommand{\\example}{text% comment\n\\} \\usepackage[GBK]{inputenc}}",
                               @"\\def\\example{\\usepackage[GBK]{inputenc}}",
                               @"\\begin{comment}\n\\usepackage[GBK]{inputenc}\n\\end{comment}",
                               @"\\verb|\\usepackage[GBK]{inputenc}|",
                               @"\\begin{verbatim}\n\\usepackage[GBK]{inputenc}\n\\end{verbatim}"]) {
        NSURL *url = [dir URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *text = [NSString stringWithFormat:@"\\documentclass{article}\n%@\n\\usepackage[latin1]{inputenc}\n%% !TEX encoding = UTF-8\n\\begin{document}Grüße\\end{document}\n", example];
        [[text dataUsingEncoding:NSISOLatin1StringEncoding] writeToURL:url atomically:YES];
        TMDocument *doc = [TMDocument documentWithContentsOfURL:url error:nil];
        TM_ASSERT_EQ_STR(doc.content, text);
        TM_ASSERT_EQ_INT(doc.textEncoding, NSISOLatin1StringEncoding);
    }
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}

TM_TEST(test_document_long_unicode_comment_header_encoding_change_reopens_losslessly) {
    NSURL *dir = tm_safetyDirectory(), *url = [dir URLByAppendingPathComponent:@"long-header.tex"];
    // 入的 UTF-8 字节含 0x85；按 Latin-1 扫描元信息时不能把它当换行。
    NSMutableString *header = [NSMutableString stringWithString:@"% 入 "];
    for (NSUInteger i = 0; i < 10000; i++) [header appendString:@"中"];
    [header appendString:@"\n"];
    NSString *body = @"\\documentclass{article}\n\\begin{document}中文\\end{document}\n";
    [[header stringByAppendingString:body] writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    TMDocument *doc = [TMDocument documentWithContentsOfURL:url error:nil];
    doc.content = [header stringByAppendingFormat:@"%% !TEX encoding = GBK\n%@", body];
    doc.isDirty = YES;
    TM_ASSERT_TRUE([doc saveCurrentFileWithError:nil]);
    TM_ASSERT_TRUE(!doc.isDirty);
    TMDocument *reopened = [TMDocument documentWithContentsOfURL:url error:nil];
    TM_ASSERT_TRUE([reopened.content isEqualToString:doc.content]);
    TM_ASSERT_EQ_INT(reopened.textEncoding, doc.textEncoding);
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}
