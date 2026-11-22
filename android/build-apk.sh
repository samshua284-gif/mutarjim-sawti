#!/bin/bash
# بناء APK «المترجم الصوتي» 1.3 — دون اتصال بالكامل:
# سمع Whisper-small + ترجمة NLLB (Transformers.js داخل WebView) + نطق Piper أصلي عبر sherpa-onnx.
# درس إلزامي من ناسخ الكلمات: MainActivity.java يُعاد كتابته هنا داخل السكربت (heredoc) — أي تعديل عليه يكون هنا.
set -e
exec > >(tee -a "$HOME/workspace/voice-translator/android/build.log") 2>&1
echo "=== VOICE TRANSLATOR BUILD (APK 1.3) START $(date) ==="

PROJ="$HOME/workspace/voice-translator/android"
APP="$HOME/workspace/voice-translator/app"
BUNDLE="$HOME/workspace/voice-translator/assets-bundle"
MTN="$HOME/workspace/mt-test/node_modules"
SDK="$HOME/android-sdk"
export JAVA_HOME="$HOME/jdk"
export PATH="$HOME/jdk/bin:$PATH"
AJAR="$SDK/platforms/android-34/android.jar"
BT="$SDK/build-tools/34.0.0"
SHERPA_JAR="$HOME/workspace/voice-translator/sherpa-aar/extracted-1.12.40/classes.jar"
KOTLIN_JAR="$SDK/cmdline-tools/latest/lib/external/org/jetbrains/kotlin/kotlin-stdlib/1.9.0/kotlin-stdlib-1.9.0.jar"
OUT="$HOME/workspace/voice-translator/voice-translator-1.3.apk"

cd "$PROJ"
mkdir -p assets/www/engines/models gen classes dex src/com/hilalsameer/voice res/values stage

# ---------- مفتاح توقيع خاص بهذا التطبيق ----------
if [ ! -f voice-release.keystore ]; then
  echo "voice-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')" > keystore-password.txt
  KSPASS="$(cat keystore-password.txt)"
  keytool -genkeypair -keystore voice-release.keystore -alias voice -keyalg RSA -keysize 2048 \
    -validity 10000 -storepass "$KSPASS" -keypass "$KSPASS" \
    -dname "CN=Hilal Sameer, OU=Voice Translator, O=Personal, L=Adam, ST=Ad Dakhiliyah, C=OM" 2>&1 | tail -1
  echo "keystore created"
fi

# ---------- أصول الويب ----------
cp "$APP/index.html" assets/www/index.html
X="$MTN/@xenova/transformers/dist"
cp "$X/transformers.min.js" assets/www/engines/
cp "$X/ort-wasm.wasm" "$X/ort-wasm-simd.wasm" "$X/ort-wasm-threaded.wasm" "$X/ort-wasm-simd-threaded.wasm" assets/www/engines/
cp "$MTN/onnxruntime-web/dist/ort-wasm-threaded.worker.js" assets/www/engines/
cp "$APP/asr-worker.js" "$APP/mt-worker.js" assets/www/engines/
rm -rf assets/www/engines/models/whisper-small assets/www/engines/models/nllb-200-distilled-600M
cp -r "$BUNDLE/whisper-small" assets/www/engines/models/whisper-small
cp -r "$BUNDLE/nllb-200-distilled-600M" assets/www/engines/models/nllb-200-distilled-600M

# ---------- أصول النطق الأصلي (خارج www — لا تُقدَّم للويب) ----------
rm -rf assets/tts
mkdir -p assets/tts/voices
for f in "$BUNDLE/piper-voices"/*.onnx "$BUNDLE/piper-voices"/*.tokens.txt; do cp "$f" assets/tts/voices/; done
cp -r "$BUNDLE/espeak-ng-data" assets/tts/espeak-ng-data
du -sh assets assets/www assets/tts

# ---------- البيان والموارد ----------
cat > AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.hilalsameer.voice"
    android:versionCode="4" android:versionName="1.3">
  <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="34"/>
  <uses-permission android:name="android.permission.RECORD_AUDIO"/>
  <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
  <application android:label="@string/app_name" android:icon="@mipmap/ic_launcher"
      android:theme="@android:style/Theme.Material.NoActionBar" android:allowBackup="false"
      android:extractNativeLibs="true">
    <activity android:name=".MainActivity" android:exported="true"
        android:configChanges="orientation|screenSize|keyboardHidden">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
EOF

cat > res/values/strings.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources><string name="app_name">المترجم الصوتي</string></resources>
EOF

# أيقونة المشغّل (تُولّد بـPIL: مربع كهرماني ودائرة كحلية وميكروفون أبيض)
python3 - <<'PYEOF'
import os
from PIL import Image, ImageDraw
sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
for name, S in sizes.items():
    img = Image.new('RGB', (S, S), (11, 16, 32))
    d = ImageDraw.Draw(img)
    m = S * 0.05
    d.rounded_rectangle([m, m, S - m, S - m], radius=S * 0.22, fill=(255, 176, 32))
    c = S / 2.0; r = S * 0.31
    d.ellipse([c - r, c - r, c + r, c + r], fill=(11, 16, 32))
    w = S * 0.13; h = S * 0.27
    d.rounded_rectangle([c - w / 2, c - h / 2 - S * 0.04, c + w / 2, c + h / 2 - S * 0.04], radius=w / 2, fill=(255, 255, 255))
    r2 = S * 0.21; lw = max(2, S // 22)
    d.arc([c - r2, c - r2 + S * 0.03, c + r2, c + r2 + S * 0.03], start=15, end=165, fill=(255, 255, 255), width=lw)
    d.line([c, c + r2 * 0.62, c, c + r2 * 0.88], fill=(255, 255, 255), width=lw)
    d.line([c - S * 0.09, c + r2 * 0.88, c + S * 0.09, c + r2 * 0.88], fill=(255, 255, 255), width=lw)
    out = 'res/mipmap-' + name
    os.makedirs(out, exist_ok=True)
    img.save(out + '/ic_launcher.png')
print('icon ok')
PYEOF

# ---------- الغلاف الأصلي (يُعاد كتابته هنا دائمًا) ----------
cat > src/com/hilalsameer/voice/MainActivity.java <<'EOF'
package com.hilalsameer.voice;

import android.Manifest;
import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.pm.PackageManager;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;
import android.webkit.ConsoleMessage;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.speech.tts.Voice;
import com.k2fsa.sherpa.onnx.GeneratedAudio;
import com.k2fsa.sherpa.onnx.OfflineTts;
import com.k2fsa.sherpa.onnx.OfflineTtsConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import org.json.JSONObject;

public class MainActivity extends Activity {
  private WebView w;
  private VoiceBridge bridge;
  private PermissionRequest pendingReq;
  private static final int MIC_REQ = 2001;
  private static final String HOST = "app.voice";
  private static final String TAG = "VOICE";

  private static final Map<String, String> MIME = new HashMap<>();
  static {
    MIME.put("html", "text/html");
    MIME.put("js", "text/javascript");
    MIME.put("mjs", "text/javascript");
    MIME.put("json", "application/json");
    MIME.put("wasm", "application/wasm");
    MIME.put("svg", "image/svg+xml");
    MIME.put("png", "image/png");
    MIME.put("jpg", "image/jpeg");
    MIME.put("css", "text/css");
    MIME.put("txt", "text/plain");
    MIME.put("onnx", "application/octet-stream");
  }

  @Override protected void onCreate(Bundle s) {
    super.onCreate(s);
    w = new WebView(this);
    WebSettings st = w.getSettings();
    st.setJavaScriptEnabled(true);
    st.setDomStorageEnabled(true);
    st.setDatabaseEnabled(true);
    st.setAllowFileAccess(true);
    st.setAllowFileAccessFromFileURLs(true);
    st.setAllowUniversalAccessFromFileURLs(true);
    st.setAllowContentAccess(true);
    st.setMediaPlaybackRequiresUserGesture(false);
    bridge = new VoiceBridge();
    w.addJavascriptInterface(bridge, "VoiceBridge");
    w.setWebViewClient(new WebViewClient() {
      @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
        Uri url = request.getUrl();
        if (url != null && HOST.equals(url.getHost())) {
          String path = url.getPath();
          if (path == null || path.equals("/")) path = "/index.html";
          String asset = "www" + path;
          Map<String, String> headers = new HashMap<>();
          headers.put("Cross-Origin-Opener-Policy", "same-origin");
          headers.put("Cross-Origin-Embedder-Policy", "credentialless");
          headers.put("Cross-Origin-Resource-Policy", "same-origin");
          try {
            InputStream is = getAssets().open(asset);
            String ext = "";
            int dot = asset.lastIndexOf('.');
            if (dot >= 0) ext = asset.substring(dot + 1).toLowerCase();
            String mime = MIME.containsKey(ext) ? MIME.get(ext) : "application/octet-stream";
            boolean text = mime.startsWith("text/") || mime.equals("application/json");
            return new WebResourceResponse(mime, text ? "UTF-8" : null, 200, "OK", headers, is);
          } catch (Exception e) {
            Log.w(TAG, "asset miss: " + asset);
            return new WebResourceResponse("text/plain", "UTF-8", 404, "Not Found", headers,
                new java.io.ByteArrayInputStream(new byte[0]));
          }
        }
        return super.shouldInterceptRequest(view, request);
      }
    });
    w.setWebChromeClient(new WebChromeClient() {
      @Override public boolean onConsoleMessage(ConsoleMessage m) {
        Log.d(TAG, "web: " + m.message());
        return true;
      }
      @Override public void onPermissionRequest(final PermissionRequest request) {
        boolean wantsAudio = false;
        for (String r : request.getResources()) {
          if (PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(r)) wantsAudio = true;
        }
        if (!wantsAudio) { request.deny(); return; }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
          request.grant(new String[]{PermissionRequest.RESOURCE_AUDIO_CAPTURE});
        } else {
          pendingReq = request;
          requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, MIC_REQ);
        }
      }
      @Override public void onPermissionRequestCanceled(PermissionRequest request) {
        if (pendingReq == request) pendingReq = null;
      }
    });
    setContentView(w);
    w.loadUrl("https://" + HOST + "/index.html");
    // تجهيز بيانات espeak في الخلفية لتسريع أول نطق
    new Thread(() -> {
      try { VoiceBridge.extractEspeak(MainActivity.this); } catch (Throwable ignored) {}
    }).start();
    // تهيئة صوت نظام الهاتف (مسار نطق ثانٍ للعربية فقط، 1.3): يفحص الجسر توفر
    // صوت عربي فعلي على الجهاز ويُعلم الصفحة عند الجاهزية.
    bridge.ensureSysTts();
  }

  @Override public void onRequestPermissionsResult(int req, String[] perms, int[] results) {
    super.onRequestPermissionsResult(req, perms, results);
    if (req == MIC_REQ && pendingReq != null) {
      if (results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) {
        pendingReq.grant(new String[]{PermissionRequest.RESOURCE_AUDIO_CAPTURE});
      } else {
        pendingReq.deny();
      }
      pendingReq = null;
    }
  }

  void evalTtsCallback(int id, boolean ok, String err) {
    String js = "window.__ttsCallback && window.__ttsCallback(" + id + "," + ok + ","
        + JSONObject.quote(err == null ? "" : err) + ")";
    w.evaluateJavascript(js, null);
  }

  @Override public void onBackPressed() {
    if (w != null && w.canGoBack()) w.goBack(); else super.onBackPressed();
  }

  @Override protected void onDestroy() {
    if (bridge != null) bridge.shutdownSysTts();
    super.onDestroy();
  }

  /* ================= جسر النطق والنسخ ================= */
  public class VoiceBridge {
    private volatile boolean stopFlag = false;
    private volatile AudioTrack track;
    private OfflineTts tts;
    private String ttsVoice;
    private final Object lock = new Object();
    // مسار صوت نظام الهاتف (1.3): Android TextToSpeech للعربية فقط — الباب
    // الوحيد لصوت عربي غير kareem دون اتصال (في كتالوج Piper صوت عربي واحد).
    private TextToSpeech sysTts;
    private volatile int sysArState = -1; // ‎-1 لم يُعرف بعد، 0 لا يوجد، 1 يوجد صوت عربي فعلي
    private volatile Voice sysArVoice;
    private volatile int sysPendingCb = -1;

    @JavascriptInterface public void copyText(final String text) {
      runOnUiThread(() -> {
        ClipboardManager cm = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        if (cm != null) {
          cm.setPrimaryClip(ClipData.newPlainText("voice", text));
          Toast.makeText(MainActivity.this, "تم النسخ", Toast.LENGTH_SHORT).show();
        }
      });
    }

    @JavascriptInterface public void stopSpeak() {
      stopFlag = true;
      AudioTrack t = track;
      if (t != null) {
        try { t.pause(); t.flush(); } catch (Exception ignored) {}
      }
      // إيقاف مسار نظام الهاتف أيضًا وإكمال ندائه المعلّق كإيقاف
      if (sysTts != null) { try { sysTts.stop(); } catch (Throwable ignored) {} }
      final int scb = sysPendingCb;
      sysPendingCb = -1;
      if (scb >= 0) runOnUiThread(() -> evalTtsCallback(scb, false, "stopped"));
    }

    // يعمل على خيط الجسر — الحظر مقبول: التوليد والتشغيل ثم ردّ النداء للصفحة
    @JavascriptInterface public void speak(final String text, final String voice, final float speed, final int cbId) {
      // مسار صوت نظام الهاتف (1.3): اختيار ar-system يُروَّت لمحرك الهاتف لا sherpa
      if ("ar-system".equals(voice)) { speakSystem(text, speed, cbId); return; }
      boolean ok = false;
      String err = "";
      synchronized (lock) {
        try {
          stopFlag = false;
          ensureTts(voice);
          GeneratedAudio audio = tts.generate(text, 0, speed);
          float[] samples = audio.getSamples();
          int sr = audio.getSampleRate();
          if (samples != null && samples.length > 0) {
            playSamples(samples, sr);
            ok = true;
          } else {
            err = "empty audio";
          }
        } catch (Throwable e) {
          err = String.valueOf(e);
          Log.e(TAG, "speak failed", e instanceof Exception ? (Exception) e : new Exception(e));
        }
      }
      final boolean fok = ok;
      final String ferr = err;
      runOnUiThread(() -> evalTtsCallback(cbId, fok, ferr));
    }

    /* ===== مسار صوت نظام الهاتف (1.3) — TextToSpeech للعربية فقط =====
       يُهيَّأ من onCreate على الخيط الرئيسي. شرط الظهور في الواجهة: صوت عربي
       فعلي على الجهاز لا يحتاج شبكة (التطبيق بلا إذن إنترنت أصلًا)؛ عند غيابه
       يبقى sysArState=0 ولا يعرض الجسر الخيار للصفحة أبدًا. */

    void ensureSysTts() {
      if (sysTts != null) return;
      try {
        sysTts = new TextToSpeech(MainActivity.this, new TextToSpeech.OnInitListener() {
          @Override public void onInit(int status) {
            if (status == TextToSpeech.SUCCESS) {
              try {
                sysTts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
                  @Override public void onStart(String uid) {}
                  @Override public void onDone(String uid) { finishSysUtterance(uid, true, ""); }
                  @Override public void onError(String uid) { finishSysUtterance(uid, false, "system tts error"); }
                });
                Voice v = findArabicVoice(sysTts);
                sysArVoice = v;
                boolean has = v != null;
                if (!has) {
                  try { has = sysTts.isLanguageAvailable(new Locale("ar")) >= TextToSpeech.LANG_AVAILABLE; }
                  catch (Throwable ignored) {}
                }
                sysArState = has ? 1 : 0;
                Log.i(TAG, "system tts ready arabic=" + has + " voice=" + (v != null ? v.getName() : "none"));
              } catch (Throwable e) {
                sysArState = 0;
                Log.e(TAG, "system tts scan failed", e);
              }
            } else {
              sysArState = 0;
              Log.e(TAG, "system tts init failed status=" + status);
            }
            runOnUiThread(() -> {
              try { w.evaluateJavascript("window.__sysTtsReady && window.__sysTtsReady()", null); }
              catch (Throwable ignored) {}
            });
          }
        });
      } catch (Throwable e) {
        sysArState = 0;
        Log.e(TAG, "system tts create failed", e);
      }
    }

    private static Voice findArabicVoice(TextToSpeech t) {
      try {
        java.util.Set<Voice> voices = t.getVoices();
        if (voices != null) {
          for (Voice v : voices) {
            try {
              if (v != null && v.getLocale() != null
                  && "ar".equals(v.getLocale().getLanguage())
                  && !v.isNetworkConnectionRequired()) return v;
            } catch (Throwable ignored) {}
          }
        }
      } catch (Throwable ignored) {}
      return null;
    }

    // للصفحة: هل يوجد صوت عربي فعلي في نظام الهاتف؟ (لا يُعرض ar-system إلا عند true)
    @JavascriptInterface public boolean arabicSystemVoiceAvailable() {
      return sysArState == 1;
    }

    // نطق عبر نظام الهاتف: سرعة المنزلق نفسها إلى setSpeechRate، والإكمال غير
    // متزامن عبر مستمع النطق — يُردّ النداء للصفحة عند انتهاء الجملة فعلًا،
    // فيعمل طابور النطق المتدفق (1.3) على هذا المسار كما على sherpa.
    private void speakSystem(final String text, final float speed, final int cbId) {
      runOnUiThread(() -> {
        try {
          if (sysTts == null || sysArState != 1) { evalTtsCallback(cbId, false, "system voice unavailable"); return; }
          stopFlag = false;
          if (sysArVoice != null) {
            sysTts.setVoice(sysArVoice);
          } else {
            int r = sysTts.setLanguage(new Locale("ar"));
            if (r == TextToSpeech.LANG_MISSING_DATA || r == TextToSpeech.LANG_NOT_SUPPORTED) {
              evalTtsCallback(cbId, false, "arabic system data missing");
              return;
            }
          }
          sysTts.setSpeechRate(speed);
          sysPendingCb = cbId;
          String uid = String.valueOf(cbId);
          Bundle params = new Bundle();
          params.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, uid);
          int rc = sysTts.speak(text, TextToSpeech.QUEUE_FLUSH, params, uid);
          if (rc != TextToSpeech.SUCCESS) {
            sysPendingCb = -1;
            evalTtsCallback(cbId, false, "system speak failed");
          }
        } catch (Throwable e) {
          sysPendingCb = -1;
          Log.e(TAG, "system speak failed", e);
          evalTtsCallback(cbId, false, String.valueOf(e));
        }
      });
    }

    private void finishSysUtterance(String uid, boolean ok, String err) {
      int cb;
      try { cb = Integer.parseInt(uid); } catch (Throwable e) { return; }
      if (sysPendingCb != cb) return; // نداء قديم أو أُكمل بالإيقاف — تجاهل
      sysPendingCb = -1;
      final int fcb = cb;
      runOnUiThread(() -> evalTtsCallback(fcb, ok, err));
    }

    void shutdownSysTts() {
      if (sysTts != null) {
        try { sysTts.stop(); sysTts.shutdown(); } catch (Throwable ignored) {}
        sysTts = null;
      }
    }

    private void playSamples(float[] samples, int sr) throws Exception {
      int minBuf = AudioTrack.getMinBufferSize(sr, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT);
      int bufSize = Math.max(minBuf * 2, 8192);
      AudioTrack t = new AudioTrack.Builder()
          .setAudioAttributes(new AudioAttributes.Builder()
              .setUsage(AudioAttributes.USAGE_MEDIA)
              .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
          .setAudioFormat(new AudioFormat.Builder()
              .setSampleRate(sr)
              .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
              .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
          .setBufferSizeInBytes(bufSize)
          .setTransferMode(AudioTrack.MODE_STREAM)
          .build();
      track = t;
      try {
        t.play();
        short[] pcm = new short[4096];
        int i = 0;
        while (i < samples.length) {
          if (stopFlag) break;
          int n = Math.min(pcm.length, samples.length - i);
          for (int j = 0; j < n; j++) {
            float v = samples[i + j];
            if (v > 1f) v = 1f; else if (v < -1f) v = -1f;
            pcm[j] = (short) (v * 32767);
          }
          int written = 0;
          while (written < n && !stopFlag) {
            int wr = t.write(pcm, written, n - written);
            if (wr < 0) throw new Exception("AudioTrack.write=" + wr);
            written += wr;
          }
          i += n;
        }
        if (!stopFlag) {
          long deadline = System.currentTimeMillis() + (samples.length * 1000L / Math.max(1, sr)) + 3000;
          while (!stopFlag && System.currentTimeMillis() < deadline) {
            if (t.getPlaybackHeadPosition() >= samples.length) break;
            Thread.sleep(40);
          }
        }
      } finally {
        try { t.stop(); } catch (Exception ignored) {}
        t.release();
        if (track == t) track = null;
      }
    }

    private void ensureTts(String voice) throws Exception {
      if (tts != null && voice.equals(ttsVoice)) return;
      File base = new File(getFilesDir(), "tts");
      File espeakDir = extractEspeak(MainActivity.this);
      // 1.3 — تقوية مسار الصوت بعد بلاغ «صوت ذكر في الحالتين»:
      // (أ) مجلد استخراج مستقل لكل صوت تحت جذر جديد كليًا (tts/v13/voices/<voiceId>/)
      //     فلا يُعاد استعمال أي ملف استخرجته 1.0–1.2 مهما كانت حالته على الجهاز.
      // (ب) الاستخراج موثّق بالحجم: لا يُقبل ملف إلا بطول أصل الـAPK بايتًا.
      // (ج) حذف مجلد الاستخراج القديم المشترك (tts/voices) مرة واحدة — ذاكرة
      //     أصول خالصة تُعاد من الـAPK عند الحاجة، فحذفها آمن ويحرّر المساحة.
      File legacyDir = new File(base, "voices");
      if (legacyDir.isDirectory()) deleteRecursive(legacyDir);
      File voiceDir = new File(new File(base, "v13/voices"), voice);
      if (!voiceDir.isDirectory()) voiceDir.mkdirs();
      File model = new File(voiceDir, "model.onnx");
      File tokens = new File(voiceDir, "tokens.txt");
      extractVerified("tts/voices/" + voice + ".onnx", model);
      extractVerified("tts/voices/" + voice + ".tokens.txt", tokens);
      if (tts != null) {
        try { tts.release(); } catch (Exception ignored) {}
        tts = null;
        ttsVoice = null;
      }
      OfflineTtsVitsModelConfig vits = new OfflineTtsVitsModelConfig();
      vits.setModel(model.getAbsolutePath());
      vits.setLexicon("");
      vits.setTokens(tokens.getAbsolutePath());
      vits.setDataDir(espeakDir.getAbsolutePath());
      vits.setDictDir("");
      OfflineTtsModelConfig mc = new OfflineTtsModelConfig();
      mc.setVits(vits);
      mc.setNumThreads(2);
      mc.setDebug(false);
      mc.setProvider("cpu");
      OfflineTtsConfig cfg = new OfflineTtsConfig();
      cfg.setModel(mc);
      cfg.setRuleFsts("");
      cfg.setRuleFars("");
      cfg.setMaxNumSentences(1);
      // AssetManager=null + مسارات ملفات مطلقة → sherpa يقرأ من نظام الملفات (newFromFile)
      tts = new OfflineTts(null, cfg);
      ttsVoice = voice;
      Log.i(TAG, "tts built voice=" + voice + " model=" + model.getAbsolutePath() + " bytes=" + model.length());
    }

    // استخراج موثّق بالحجم (1.3): يُقبل الملف المستخرج فقط إن طابق طولُه طولَ
    // الأصل داخل الـAPK بايتًا (الأصول مخزّنة دون ضغط فيعمل openFd)؛ عند الاختلاف
    // يُحذف ويُعاد نسخه مرة واحدة، فإن بقي الاختلاف رُفع خطأ مرئي بدل نطقٍ صامت
    // بنموذج غير موثّق. إن تعذّر openFd سقطنا إلى فحص الوجود كما في 1.0–1.2.
    private void extractVerified(String assetPath, File dest) throws Exception {
      long expected = -1;
      try {
        android.content.res.AssetFileDescriptor afd = getAssets().openFd(assetPath);
        expected = afd.getLength();
        afd.close();
      } catch (Throwable ignored) {}
      for (int attempt = 0; attempt < 2; attempt++) {
        if (dest.exists() && (expected < 0 || dest.length() == expected)) return;
        if (dest.exists()) dest.delete();
        copyAsset(MainActivity.this, assetPath, dest);
      }
      if (expected >= 0 && dest.length() != expected) {
        throw new Exception("asset size mismatch: " + assetPath + " got=" + dest.length() + " want=" + expected);
      }
    }

    private static void deleteRecursive(File f) {
      if (f.isDirectory()) {
        File[] kids = f.listFiles();
        if (kids != null) for (File k : kids) deleteRecursive(k);
      }
      try { f.delete(); } catch (Exception ignored) {}
    }

    static File extractEspeak(Activity act) throws Exception {
      File base = new File(act.getFilesDir(), "tts");
      File dir = new File(base, "espeak-ng-data");
      File sentinel = new File(base, "espeak.done");
      if (sentinel.exists() && dir.isDirectory()) return dir;
      extractAssetDir(act, "tts/espeak-ng-data", dir);
      new FileOutputStream(sentinel).close();
      return dir;
    }

    static void extractAssetDir(Activity act, String assetPath, File destDir) throws Exception {
      String[] list = act.getAssets().list(assetPath);
      if (list == null) throw new Exception("missing asset dir: " + assetPath);
      if (!destDir.isDirectory()) destDir.mkdirs();
      for (String name : list) {
        String child = assetPath + "/" + name;
        File out = new File(destDir, name);
        String[] sub = act.getAssets().list(child);
        if (sub != null && sub.length > 0) {
          extractAssetDir(act, child, out);
        } else if (!out.exists()) {
          copyAsset(act, child, out);
        }
      }
    }

    static void copyAsset(Activity act, String assetPath, File dest) throws Exception {
      File parent = dest.getParentFile();
      if (parent != null && !parent.isDirectory()) parent.mkdirs();
      File tmp = new File(dest.getAbsolutePath() + ".tmp");
      try (InputStream in = act.getAssets().open(assetPath);
           FileOutputStream out = new FileOutputStream(tmp)) {
        byte[] buf = new byte[1 << 16];
        int n;
        while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
      }
      if (!tmp.renameTo(dest)) throw new Exception("rename failed: " + dest);
    }
  }
}
EOF

# ---------- التجميع والربط والديكس ----------
"$BT/aapt2" compile --dir res -o res.zip
"$BT/aapt2" link -o unsigned.apk -I "$AJAR" --manifest AndroidManifest.xml res.zip
javac -encoding UTF-8 -cp "$AJAR:$SHERPA_JAR:$KOTLIN_JAR" -d classes src/com/hilalsameer/voice/MainActivity.java
"$BT/d8" --min-api 24 --lib "$AJAR" --output dex $(find classes -name '*.class') "$SHERPA_JAR" "$KOTLIN_JAR"

# مكتبات arm64-v8a فقط
rm -rf stage/lib
mkdir -p stage/lib/arm64-v8a
cp "$HOME/workspace/voice-translator/sherpa-aar/extracted-1.12.40/jni/arm64-v8a/"*.so stage/lib/arm64-v8a/
ls -la stage/lib/arm64-v8a/

# إضافة الديكس والمكتبات والأصول دون ضغط (النماذج لا تنضغط أصلًا، والقراءة المباشرة أسرع)
(cd dex && zip -0 -q ../unsigned.apk classes.dex)
(cd stage && zip -0 -q -r ../unsigned.apk lib)
zip -0 -q -r unsigned.apk assets

"$BT/zipalign" -f 4 unsigned.apk aligned.apk

KSPASS="$(cat keystore-password.txt)"
"$BT/apksigner" sign --ks voice-release.keystore --ks-pass "pass:$KSPASS" --key-pass "pass:$KSPASS" \
  --out "$OUT" aligned.apk
"$BT/apksigner" verify --print-certs "$OUT" | head -3
"$BT/aapt2" dump badging "$OUT" 2>/dev/null | grep -E "package:|application-label:" | head -2
ls -la "$OUT"
sha256sum "$OUT"
echo "=== VOICE TRANSLATOR BUILD OK ==="
