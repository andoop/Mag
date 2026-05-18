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

  test('catalog match resolves alibaba connection to qwen provider aliases',
      () {
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

  test('mag provider uses opencode catalog cost for public free models', () {
    final catalog = [
      const ProviderInfo(
        id: 'opencode',
        name: 'OpenCode',
        models: {
          'cost-zero-model': ProviderModelInfo(
            id: 'cost-zero-model',
            name: 'Cost Zero',
            cost: ProviderModelCost(input: 0, output: 0),
          ),
          'paid-free-suffix-free': ProviderModelInfo(
            id: 'paid-free-suffix-free',
            name: 'Paid Despite Suffix',
            cost: ProviderModelCost(input: 1, output: 1),
          ),
        },
      ),
    ];
    final response = buildProviderListResponse(
      catalog: catalog,
      config: ModelConfig(
        currentProviderId: 'mag',
        currentModelId: 'cost-zero-model',
        connections: [
          ProviderConnection(
            id: 'mag',
            name: 'Mag',
            baseUrl: 'https://opencode.ai/zen/v1',
            apiKey: '',
            models: const ['paid-free-suffix-free'],
          ),
        ],
        visibilityRules: const [],
      ),
    );
    final mag = response.all.firstWhere((provider) => provider.id == 'mag');

    expect(mag.models.keys, contains('cost-zero-model'));
    expect(mag.models.keys, isNot(contains('paid-free-suffix-free')));
    expect(
        isProviderListModelFree(
          providerList: response,
          providerId: 'mag',
          modelId: 'cost-zero-model',
        ),
        isTrue);
  });

  test('mag provider keeps paid catalog models when api key is present', () {
    final catalog = [
      const ProviderInfo(
        id: 'opencode',
        name: 'OpenCode',
        models: {
          'cost-zero-model': ProviderModelInfo(
            id: 'cost-zero-model',
            name: 'Cost Zero',
            cost: ProviderModelCost(input: 0, output: 0),
          ),
          'paid-model': ProviderModelInfo(
            id: 'paid-model',
            name: 'Paid',
            cost: ProviderModelCost(input: 1, output: 1),
          ),
        },
      ),
    ];
    final response = buildProviderListResponse(
      catalog: catalog,
      config: ModelConfig(
        currentProviderId: 'mag',
        currentModelId: 'paid-model',
        connections: [
          ProviderConnection(
            id: 'mag',
            name: 'Mag',
            baseUrl: 'https://opencode.ai/zen/v1',
            apiKey: 'test-key',
            models: const [],
          ),
        ],
        visibilityRules: const [],
      ),
    );
    final mag = response.all.firstWhere((provider) => provider.id == 'mag');

    expect(mag.models.keys, contains('cost-zero-model'));
    expect(mag.models.keys, contains('paid-model'));
  });

  test('mag catalog match resolves against opencode provider', () {
    final catalog = [
      const ProviderInfo(
        id: 'opencode',
        name: 'OpenCode',
        models: {
          'cost-zero-model': ProviderModelInfo(
            id: 'cost-zero-model',
            name: 'Cost Zero',
            cost: ProviderModelCost(input: 0, output: 0),
          ),
        },
      ),
    ];

    final match = resolveCatalogModelMatch(
      catalog: catalog,
      providerId: 'mag',
      modelId: 'cost-zero-model',
    );

    expect(match.source, 'catalog');
    expect(match.matchedProviderId, 'opencode');
    expect(match.matchedModelId, 'cost-zero-model');
  });
}
