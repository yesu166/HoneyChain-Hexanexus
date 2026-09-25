import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';

/// One chat turn as sent to `POST /api/v1/ai/chat`.
///
/// Mirrors `backend/app/schemas/ai.py::AIChatMessage` — a plain
/// role + content transcript. All tool execution and Gemini reasoning stays
/// server-side; the app never sees hive tool payloads.
class AskChatMessage {
  const AskChatMessage({required this.role, required this.content});

  /// `user` or `assistant`.
  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  factory AskChatMessage.fromJson(Map<String, dynamic> json) => AskChatMessage(
    role: json['role'] as String? ?? 'user',
    content: json['content'] as String? ?? '',
  );
}

/// Parsed `AIChatResponse`: assistant text plus how many validated HoneyChain
/// tools the backend executed while producing it (0 when it only reasoned).
class AskChatReply {
  const AskChatReply({
    required this.reply,
    required this.toolCount,
    this.requestId,
  });

  final String reply;
  final int toolCount;
  final String? requestId;

  factory AskChatReply.fromJson(Map<String, dynamic> json) {
    final reply = json['reply'];
    if (reply is! String) {
      // Malformed body — fail explicitly instead of showing an empty bubble.
      throw const ApiException(
        ApiExceptionKind.unknown,
        'Malformed Ask My Bee response',
      );
    }
    final toolCount = json['tool_count'];
    return AskChatReply(
      reply: reply,
      toolCount: toolCount is int ? toolCount : 0,
      requestId: json['request_id'] as String?,
    );
  }
}

/// Parsed `GET /api/v1/ai/status` payload. Never contains secrets.
class AskBackendStatus {
  const AskBackendStatus({
    required this.enabled,
    required this.configured,
    this.model = '',
  });

  final bool enabled;
  final bool configured;
  final String model;

  factory AskBackendStatus.fromJson(Map<String, dynamic> json) =>
      AskBackendStatus(
        enabled: json['enabled'] as bool? ?? false,
        configured: json['configured'] as bool? ?? false,
        model: json['model'] as String? ?? '',
      );
}

/// Ask My Bee operations against the authenticated FastAPI backend.
///
/// Abstract so tests can fake it; production code uses [AskMyBeeHttpApi].
abstract class AskMyBeeApi {
  /// Sends the transcript to `POST /api/v1/ai/chat` and returns the reply.
  ///
  /// [language] is the app-selected language code (en/hi/ta/bn/pa/ml/mr);
  /// the backend uses it to make the assistant reply in that language.
  Future<AskChatReply> sendChat(List<AskChatMessage> messages, {String? language});

  /// Reads `GET /api/v1/ai/status` (enabled / configured / model name).
  Future<AskBackendStatus> fetchStatus();
}

/// HTTP implementation on the shared [ApiClient] stack: same JWT bearer
/// token, same error mapping (401/403/422/429/5xx/timeout → ApiException).
///
/// Gemini and Supabase credentials never appear in the app — this only ever
/// talks to the HoneyChain FastAPI backend.
class AskMyBeeHttpApi implements AskMyBeeApi {
  AskMyBeeHttpApi(this._client);

  final ApiClient _client;

  @override
  Future<AskChatReply> sendChat(List<AskChatMessage> messages, {String? language}) async {
    final body = await _client.postJson(
      '/api/v1/ai/chat',
      body: {
        'messages': messages.map((m) => m.toJson()).toList(),
        if (language != null && language.isNotEmpty) 'language': language,
      },
    );
    return AskChatReply.fromJson(body);
  }

  @override
  Future<AskBackendStatus> fetchStatus() async {
    final body = await _client.getJson('/api/v1/ai/status');
    return AskBackendStatus.fromJson(body);
  }
}
