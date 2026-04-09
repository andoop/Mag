part of '../models.dart';

/// OpenCode `ProviderTransform.OUTPUT_TOKEN_MAX`（未设置实验 flag 时默认 32k）。
const int kMagOutputTokenHardCap = 32000;

/// OpenCode `session/overflow.ts` `COMPACTION_BUFFER`.
const int kOpenCodeCompactionBuffer = 20000;

/// OpenCode `util/token.ts`：`Math.round(length / 4)`。
int estimateOpenCodeCharsAsTokens(int charCount) =>
    math.max(0, (charCount / 4).round());

/// 对即将发给模型的 `messages` JSON 做 token 粗估。
///
/// 旧版用 `max(bytes/3, chars/2)` 对中文过度高估（中文 UTF-8 每字 3 字节，
/// 导致估算约为 1 char = 1 token，而实际 CJK tokenizer 约 1.5-2 字符/token），
/// 引发不必要的频繁压缩。新版对 CJK 密集文本使用更宽松的系数。
int estimateSerializedMessagesTokens(List<Map<String, dynamic>> messages) {
  if (messages.isEmpty) return 0;
  final json = jsonEncode(messages);
  final bytes = utf8.encode(json).length;
  final cjkRatio = bytes > 0 ? (bytes - json.length) / bytes : 0.0;
  // High CJK ratio (>30%): multi-byte chars dominate, use gentler divisor
  if (cjkRatio > 0.30) {
    return (bytes / 4.5).ceil();
  }
  final fromBytes = (bytes / 3).ceil();
  final fromChars = (json.length / 2).ceil();
  return math.max(fromBytes, fromChars);
}

/// 与 OpenCode `overflow.ts` 中「可放入上下文」的 input 预算一致（无 `limit.input` 时为 `context - maxOut`）。
int usableInputTokensForModel(String model, {int? limitInput}) {
  final context = inferContextWindow(model);
  if (context == 0) return 1 << 30;
  final maxOut = inferMaxOutputTokens(model);
  final reserved = math.min(kOpenCodeCompactionBuffer, maxOut);
  return limitInput != null ? limitInput - reserved : context - maxOut;
}

/// 与 OpenCode `session/overflow.ts` `isOverflow` 一致（换模型时用**当前**模型的 limit）。
///
/// [limitInput] 对应 models.dev `limit.input`；Mag 暂无该配置时传 null，走
/// `usable = context - maxOutputTokens(model)`。
bool isContextOverflowForCompaction({
  required ModelUsage tokens,
  required String model,
  int? limitInput,
  bool compactionAutoDisabled = false,
}) {
  if (compactionAutoDisabled) return false;
  final context = inferContextWindow(model);
  if (context == 0) return false;
  final count = tokens.opencodeCompactionCount;
  final usable = usableInputTokensForModel(model, limitInput: limitInput);
  return count >= usable;
}

/// 最近一条**已完成**（含 stepFinish）的 assistant 的用量，供新一轮用户消息前做 OpenCode 式 overflow 判断。
ModelUsage? modelUsageFromLatestCompletedAssistant({
  required List<MessageInfo> messages,
  required List<MessagePart> parts,
}) {
  final assistants = messages.where((m) => m.role == SessionRole.assistant).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  for (final msg in assistants) {
    MessagePart? finish;
    for (final p in parts) {
      if (p.messageId != msg.id || p.type != PartType.stepFinish) continue;
      if (finish == null || p.createdAt >= finish.createdAt) {
        finish = p;
      }
    }
    if (finish == null) continue;
    final tok = finish.data['tokens'];
    if (tok is Map<String, dynamic>) {
      return ModelUsage.fromJson(tok);
    }
  }
  return null;
}

/// 与 OpenCode `ProviderTransform.maxOutputTokens` 同思路：按模型 id 推断单次 completion 上限。
int inferMaxOutputTokens(String model) {
  final lower = model.toLowerCase();
  int cap;
  if (lower.contains('o1') || lower.contains('o3') || lower.contains('o4')) {
    cap = 100000;
  } else if (lower.contains('gpt-4.1') || lower.contains('gpt-4-1')) {
    cap = 32768;
  } else if (lower.contains('gpt-4o') || lower.contains('gpt-4-turbo')) {
    cap = 16384;
  } else if (lower.contains('gpt-4')) {
    cap = 8192;
  } else if (lower.contains('claude')) {
    if (lower.contains('opus-4') ||
        lower.contains('sonnet-4') ||
        lower.contains('haiku-4')) {
      cap = 64000;
    } else {
      cap = 8192;
    }
  } else if (lower.contains('gemini')) {
    cap = 8192;
  } else if (lower.contains('deepseek-reasoner')) {
    cap = 8192;
  } else if (lower.contains('deepseek')) {
    cap = 8192;
  } else if (lower.contains('minimax')) {
    cap = 131072;
  } else if (lower.contains('qwen')) {
    cap = 8192;
  } else if (lower.contains('gpt-3.5')) {
    cap = 4096;
  } else {
    cap = 8192;
  }
  return math.min(cap, kMagOutputTokenHardCap);
}

/// 与 OpenCode 模型 `limit.context` 一致：按模型 id 推断上下文窗口（用于压缩阈值与 max_tokens 封顶）。
int inferContextWindow(String model) {
  final lower = model.toLowerCase();
  final kSuffix = RegExp(r'\b(\d{1,4})k\b').firstMatch(lower);
  if (kSuffix != null) {
    final k = int.tryParse(kSuffix.group(1)!);
    if (k != null && k >= 8 && k <= 2000) {
      return k * 1024;
    }
  }
  if (lower.contains('gemini')) return 1000000;
  if (lower.contains('gpt-4.1')) return 1047576;
  if (lower.contains('o1') || lower.contains('o3') || lower.contains('o4')) {
    return 200000;
  }
  if (lower.contains('claude')) return 200000;
  if (lower.contains('gpt-4o')) return 128000;
  if (lower.contains('gpt-4')) return 128000;
  if (lower.contains('gpt-3.5')) {
    if (lower.contains('16k')) return 16384;
    return 4096;
  }
  // DeepSeek Chat / Reasoner 常见为 128k；若模型名含 `64k` 等则由上方 `\d+k` 规则覆盖。
  if (lower.contains('deepseek-reasoner')) return 131072;
  if (lower.contains('deepseek')) return 131072;
  if (lower.contains('minimax')) return 1000000;
  return 128000;
}

String formatTokenCount(int tokens) {
  if (tokens >= 1000000) {
    final value =
        (tokens / 1000000).toStringAsFixed(tokens % 1000000 == 0 ? 0 : 1);
    return '${value}M';
  }
  if (tokens >= 1000) {
    final value = (tokens / 1000).toStringAsFixed(tokens % 1000 == 0 ? 0 : 1);
    return '${value}K';
  }
  return '$tokens';
}
