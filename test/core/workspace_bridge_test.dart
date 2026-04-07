import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/workspace_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final bridge = WorkspaceBridge.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('workspace_bridge_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('local tree backend supports core file operations', () async {
    final treeUri = tempDir.path;

    await bridge.writeText(
      treeUri: treeUri,
      relativePath: 'lib/main.dart',
      content: 'void main() {}\n',
    );
    await bridge.writeText(
      treeUri: treeUri,
      relativePath: 'README.md',
      content: '# Sandbox\nhello sandbox\n',
    );

    expect(
      await bridge.readText(treeUri: treeUri, relativePath: 'lib/main.dart'),
      contains('void main'),
    );

    final rootEntries = await bridge.listDirectory(treeUri: treeUri);
    expect(rootEntries.map((item) => item.path), containsAll(['README.md', 'lib']));

    final search = await bridge.searchEntries(
      treeUri: treeUri,
      pattern: '**/*.dart',
    );
    expect(search.any((item) => item.path == 'lib/main.dart'), isTrue);

    final grep = await bridge.grepText(
      treeUri: treeUri,
      pattern: 'sandbox',
    );
    expect(grep.any((item) => item['path'] == 'README.md'), isTrue);

    final renamed = await bridge.renameEntry(
      treeUri: treeUri,
      relativePath: 'README.md',
      newName: 'NOTES.md',
    );
    expect(renamed.path, 'NOTES.md');

    final copied = await bridge.copyEntry(
      treeUri: treeUri,
      fromPath: 'lib/main.dart',
      toPath: 'lib/main_copy.dart',
    );
    expect(copied.path, 'lib/main_copy.dart');

    final moved = await bridge.moveEntry(
      treeUri: treeUri,
      fromPath: 'lib/main_copy.dart',
      toPath: 'src/main_copy.dart',
    );
    expect(moved.path, 'src/main_copy.dart');
    expect(await File('${tempDir.path}/src/main_copy.dart').exists(), isTrue);

    await bridge.deleteEntry(
      treeUri: treeUri,
      relativePath: 'src',
    );
    expect(
      await bridge.getEntry(treeUri: treeUri, relativePath: 'src/main_copy.dart'),
      isNull,
    );

    expect(
      await bridge.resolveFilesystemPath(treeUri: treeUri),
      tempDir.path,
    );
  });
}
