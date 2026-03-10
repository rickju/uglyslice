import 'package:functions_framework/serve.dart';
import 'package:ugly_slice_backend/ingest_handler.dart';

Future<void> main(List<String> args) async =>
    serve(args, _nameToFunctionTarget);

FunctionTarget? _nameToFunctionTarget(String name) {
  return switch (name) {
    'ingestCourse' => FunctionTarget.http(ingestCourse),
    _ => null,
  };
}
