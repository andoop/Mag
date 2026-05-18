# AI Web Runtime

Mag can run AI-generated HTML previews and expose selected native mobile capabilities through `window.MagNative`.

This makes generated pages more than static demos: they can ask the user to pick files, take a photo, record audio, or record video inside the app.

## Available APIs

| API | Native Capability |
|-----|-------------------|
| `window.MagNative.pickFiles(options)` | Pick files from the device. |
| `window.MagNative.capturePhoto(options)` | Capture a photo in app. |
| `window.MagNative.recordAudio(options)` | Record audio in app. |
| `window.MagNative.recordVideo(options)` | Record video in app. |
| `window.MagNative.generateQrCode(options)` | Generate a QR code SVG/data URL in the HTML runtime. |

Captured file inputs are also bridged:

- `input[type=file]` can call file picking.
- `input[accept=image/*][capture]` can call photo capture.
- `input[accept=audio/*][capture]` can call audio recording.
- `input[accept=video/*][capture]` can call video recording.

## Example

```html
<button id="record">Record audio</button>
<audio id="preview" controls></audio>

<script>
  document.getElementById('record').onclick = async () => {
    const file = await window.MagNative.recordAudio();
    document.getElementById('preview').src = file.url;
  };
</script>
```

```html
<img id="qr" alt="QR code">

<script>
  document.getElementById('qr').onclick = async () => {
    const qr = await window.MagNative.generateQrCode({
      text: location.href,
      size: 256,
      errorCorrectionLevel: 'M'
    });
    document.getElementById('qr').src = qr.dataUrl;
  };
</script>
```

## Design Rules

- Native capabilities require a user gesture.
- Returned files are runtime-scoped temporary URLs.
- Generated pages should feature-detect `window.MagNative`.
- Pages should degrade gracefully when a capability is unavailable.
- Sensitive native actions remain user-visible.
- QR generation is pure Dart and returns SVG text plus a `data:image/svg+xml` URL.

---

# AI 网页运行时

Mag 允许 AI 生成的 HTML 页面调用部分原生移动能力，例如选文件、拍照、录音和录像。这让网页原型可以直接变成可交互的端上体验。

页面应优先检测 `window.MagNative` 是否存在，并在能力不可用时给出降级提示。

二维码可通过 `window.MagNative.generateQrCode({ text, size })` 生成，返回 `svg` 和 `dataUrl`，可直接赋给 `<img>` 展示。
