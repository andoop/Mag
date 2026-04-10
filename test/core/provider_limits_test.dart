import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/models.dart';

void main() {
  test('qwen plus fallback limit returns full context input output', () {
    final limit = inferProviderModelLimitFallback('qwen3-coder-plus');

    expect(limit.context, 1000000);
    expect(limit.output, 32000);
    expect(limit.input, 968000);
  });

  test('qwen heuristic normalizes decorated model ids', () {
    expect(inferContextWindow('qwen/qwen3.6-plus:latest'), 1000000);
    expect(inferMaxOutputTokens('qwen/qwen3.6-plus:latest'), 32000);
  });

  test('catalog match resolves alibaba connection to qwen provider aliases', () {
    final catalog = [
      ProviderInfo(
        id: 'qwen',
        name: 'Qwen',
        models: {
          'qwen3-coder-plus-2025-09-23': const ProviderModelInfo(
            id: 'qwen3-coder-plus-2025-09-23',
            name: 'Qwen3 Coder Plus',
            limit: ProviderModelLimit(
              context: 1000000,
              input: 997952,
              output: 65536,
            ),
          ),
        },
      ),
    ];
    final connection = ProviderConnection(
      id: 'alibaba-cn',
      name: 'Alibaba',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      apiKey: '',
      models: const ['qwen3-coder-plus'],
    );

    final match = resolveCatalogModelMatch(
      catalog: catalog,
      connection: connection,
      modelId: 'qwen3-coder-plus',
    );

    expect(match.fromCatalog, isTrue);
    expect(match.matchedProviderId, 'qwen');
    expect(match.matchedModelId, 'qwen3-coder-plus-2025-09-23');
    expect(match.catalogModel?.limit.context, 1000000);
    expect(match.catalogModel?.limit.output, 65536);
  });
}
