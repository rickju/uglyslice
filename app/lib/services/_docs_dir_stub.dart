import 'dart:io';

Future<Directory> getDocsDir() async =>
    Directory.systemTemp.createTempSync('ugly_slice_test');
