# Analytics Integration

`mobile_agent` 现在有一层与具体厂商解耦的统计封装，入口在 `lib/core/analytics.dart`。应用自己的事件定义集中在 `lib/core/app_analytics.dart`，运行时初始化在 `lib/core/analytics_bootstrap.dart`。

## 当前结构

- `AnalyticsService`: 统一对外的统计接口
- `AnalyticsAdapter`: 单个统计后端的适配器协议
- `AnalyticsEvent` / `AnalyticsScreen`: 通用事件与页面模型
- `FirebaseAnalyticsAdapter`: Firebase 风格适配器
- `SensorsAnalyticsAdapter`: 神策风格适配器
- `NoopAnalyticsAdapter`: 默认空实现，不会影响现有功能
- `AppAnalytics`: 统一管理本应用事件名、页面名和属性结构
- `createAnalyticsBootstrap()`: 根据运行配置选择真实统计后端并产出静态埋点配置

应用启动时，`AppController` 会：

1. 初始化 analytics
2. 生成并持久化一个匿名 `distinct_id`
3. 自动设置打包时注入的用户属性与公共事件属性
4. 自动上报首屏和关键事件

当前已接入的关键事件包括：

- `app_initialized`
- `first_install`
- `workspace_opened`
- `workspace_left`
- `project_created`
- `project_renamed`
- `project_deleted`
- `session_created`
- `prompt_submitted`
- `provider_connected`
- `provider_disconnected`
- `model_selected`
- `shortcut_preview_opened`
- 页面浏览：`project_home` / `workspace_home`

当前已内置的用户属性 / 公共事件属性：

- `channel`
- `gray_group`
- `is_internal_user`

新增埋点时，优先在 `AppAnalytics` 中增加一个新的 builder，再由业务代码调用 `track(...)` / `trackScreen(...)`。这样可以避免事件名散落在各处，后续改名、补属性或做数据口径治理时更容易维护。

## 为什么先做成委托式适配器

项目当前 `pubspec.yaml` 的 Dart 约束还是 `<3.0.0`。而最新官方 Flutter Firebase 包已经要求 Dart 3，因此这里先把统计层做成“可插拔”的纯 Dart 抽象，避免现在为了埋点把整套 Flutter SDK 升级链路一起带进来。

等项目升级到 Dart 3 后，可以在应用入口把真实 SDK 挂进来。

## 接 Firebase

升级 Flutter / Dart 版本并完成原生 Firebase 初始化后，可以在创建 `AppController` 时注入：

```dart
final analytics = AnalyticsService.firebase(
  onTrackEvent: (eventName, properties) async {
    await firebaseAnalytics.logEvent(name: eventName, parameters: properties);
  },
  onTrackScreen: (screenName, properties) async {
    await firebaseAnalytics.logScreenView(
      screenName: screenName,
      parameters: properties,
    );
  },
  onIdentify: (userId, traits) async {
    await firebaseAnalytics.setUserId(id: userId);
    for (final entry in traits.entries) {
      await firebaseAnalytics.setUserProperty(
        name: entry.key,
        value: entry.value?.toString(),
      );
    }
  },
  onSetUserProperties: (properties) async {
    for (final entry in properties.entries) {
      await firebaseAnalytics.setUserProperty(
        name: entry.key,
        value: entry.value?.toString(),
      );
    }
  },
);
```

## 已接入神策

项目已经加入 `sensors_analytics_flutter_plugin`。现在有两种启用方式：

### 方式一：Android 打包配置

Android 会优先读取 `android/local.properties` 里的配置，并在打包时注入到 `BuildConfig`，Flutter 启动后再通过 method channel 读取。

可以在 `android/local.properties` 中配置：

```properties
mag.analytics.provider=sensors
mag.analytics.sensors.serverUrl=https://your-project.example.com/sa?project=default
mag.analytics.sensors.enableLog=true
mag.analytics.sensors.flushIntervalMs=15000
mag.analytics.sensors.flushBulkSize=100
mag.analytics.channel=official
mag.analytics.grayGroup=gray_a
mag.analytics.isInternalUser=false
```

### 方式二：dart-define 覆盖

`dart-define` 的优先级高于 Android 本地打包配置，适合 CI 或临时覆盖：

```bash
flutter run \
  --dart-define=MAG_ANALYTICS_PROVIDER=sensors \
  --dart-define=MAG_SENSORS_SERVER_URL=https://your-project.example.com/sa?project=default \
  --dart-define=MAG_SENSORS_ENABLE_LOG=true \
  --dart-define=MAG_ANALYTICS_CHANNEL=official \
  --dart-define=MAG_ANALYTICS_GRAY_GROUP=gray_a \
  --dart-define=MAG_ANALYTICS_IS_INTERNAL_USER=false
```

可选参数：

- `MAG_SENSORS_FLUSH_INTERVAL_MS`，默认 `15000`
- `MAG_SENSORS_FLUSH_BULK_SIZE`，默认 `100`
- `MAG_ANALYTICS_CHANNEL`
- `MAG_ANALYTICS_GRAY_GROUP`
- `MAG_ANALYTICS_IS_INTERNAL_USER`

如果未设置 `MAG_SENSORS_SERVER_URL`，会自动回退到 `noop`，不会影响 App 正常运行。

## 已接入自定义服务器上报

项目现在也支持直接把埋点 POST 到你自己的服务器，不依赖 Firebase / 神策。

### Android `local.properties` 配置

```properties
mag.analytics.provider=custom
mag.analytics.custom.serverUrl=https://your-domain.example.com/mobile-analytics
mag.analytics.custom.apiKey=
mag.analytics.custom.apiKeyHeader=x-api-key
mag.analytics.channel=official
mag.analytics.grayGroup=gray_a
mag.analytics.isInternalUser=false
```

### `dart-define` 配置

```bash
flutter run \
  --dart-define=MAG_ANALYTICS_PROVIDER=custom \
  --dart-define=MAG_CUSTOM_ANALYTICS_SERVER_URL=https://your-domain.example.com/mobile-analytics \
  --dart-define=MAG_CUSTOM_ANALYTICS_API_KEY=your-secret \
  --dart-define=MAG_CUSTOM_ANALYTICS_API_KEY_HEADER=x-api-key
```

### 客户端 POST 协议

客户端会对同一个地址发送 `POST` 请求，`Content-Type` 为 `application/json`。如果配置了 API Key，会带上你指定的请求头。

不同操作会发送以下几类 `type`：

- `identify`
- `user_properties`
- `event`
- `screen`
- `reset`

示例：

```json
{
  "type": "event",
  "sentAt": "2026-05-19T10:00:00.000Z",
  "source": {
    "sdk": "mobile_agent",
    "adapter": "custom"
  },
  "event": "prompt_submitted",
  "properties": {
    "distinct_id": "user-abc",
    "channel": "official",
    "gray_group": "gray_a",
    "is_internal_user": false,
    "provider": "openai",
    "model": "gpt-4.1"
  }
}
```

你现在不需要写服务端代码也能先把客户端接好；等后端准备好后，只要按这个 JSON 协议接收并入库即可。

当前神策桥接逻辑：

- `initialize` -> `SensorsAnalyticsFlutterPlugin.init(...)`
- `identify` -> `SensorsAnalyticsFlutterPlugin.identify(...)`
- `setUserProperties` -> `profileSet(...)`
- `trackEvent` -> `track(...)`
- `trackScreen` -> `trackViewScreen(...)`
- `dispose` -> `flush()`

## 手动接神策

如果你想自行调整接法，当前桥接实现的基础对应关系如下：

完成神策 Flutter SDK 初始化后，可以切成：

```dart
final analytics = AnalyticsService.sensors(
  onTrackEvent: (eventName, properties) async {
    await sensors.track(eventName, properties);
  },
  onTrackScreen: (screenName, properties) async {
    await sensors.trackViewScreen(screenName, properties);
  },
  onIdentify: (userId, traits) async {
    await sensors.login(userId);
    if (traits.isNotEmpty) {
      await sensors.profileSet(traits);
    }
  },
  onSetUserProperties: (properties) async {
    await sensors.profileSet(properties);
  },
  onReset: () async {
    await sensors.logout();
  },
);
```

## 推荐做法

- 海外为主：优先接 Firebase
- 国内为主：优先接神策
- 双轨上报：`AnalyticsService(adapters: [...])` 同时挂两个适配器

这样业务代码不需要知道底层到底是 Firebase、神策，还是两者同时上报。
