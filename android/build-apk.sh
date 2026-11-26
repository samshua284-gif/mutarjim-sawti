#!/bin/bash
# بناء APK «المترجم الصوتي» 1.13 — دون اتصال بالكامل:
# سمع أصلي عبر sherpa-onnx بسلسلة سقوط 1.4/1.5: Whisper-small أصليًا
# ثم عامل ويب Transformers.js عند فشل الأصلي (أُزيلت أذن 1.6 التجريبية
# كليًا في 1.7 — ملفات وجسرًا — بحكم Hilal التجريبي على هاتفه)
# + ترجمة NLLB (Transformers.js داخل WebView) + نطق Piper أصلي عبر sherpa-onnx
# + (1.8) مرحلة ثانية: بلوتوث كلاسيك (RFCOMM) بين هاتفين — الترجمة تُحسب
# على هاتف المرسل، ويعبر البلوتوث النصان ومقطع صوت المتكلم الأصلي فقط.
# + (1.9) ترقيتان تلقائيتان بأمرَي Hilal المتتابعين في الصفحة
# (app/index.html): قاعدة «الن»←«الآن» وزوج «سلطانة أمان»←«سلطنة عُمان»
# (مع ترقية مدخل oman-full) صارتا تصحيحًا تلقائيًا بدل اقتراح معلّق —
# بقية 1.8 حرفيًا.
# + (1.13) قاعدة إخراج عربي في الصفحة (arTargetFix): كسرة تاء «أنتِ» في ترجمة NLLB العربية ← فتحة «أنتَ» — من واقعة Hilal الحية «أين أنتِ؟» التي نطقها النظام «anti»؛ الحروف ثابتة والتشكيل وحده يتغير (مُثبتة بالنقاط الرمزية U+0650←U+064E وببطارية حالات). تُطبق على مخرجات الترجمة العربية في مساراتها الثلاثة (عبارات ثابتة/جزئيات/نتيجة نهائية) ولا تمس النص المسموع. بقية 1.12 حرفيًا.
# + (1.12) قاعدة «were»←«where» صارت ذكية حارسة للسياق بأمر Hilal («لماذا لا تبقى were في سياقها الحقيقي»): تنقلب بدليل الجيران فقط (فعل مساعد أو now بعدها) وتبقى في سياق الماضي الحقيقي — مُثبتة بـ23 حالة اختبار آلية (6 قلب + 14 إبقاء + سلامة قاعدتي العربية) قبل البناء. بقية 1.11 حرفيًا.
# + (1.11) بأوامر Hilal من لقطات اختباره الحي: حذف صوت الذكر من العربية (بقي نظام الهاتف وحده) وحذف ryan من الإنجليزية (بقيت amy)، وقاعدة تلقائية ثالثة في الصفحة: «were» ← «where» في النص الإنجليزي المسموع (wordRuleFix).
# + (1.10) سطر تلميح واحد في الصفحة تحت شارات الحالة بأمر Hilal الحرفي:
# «الترجمة أكثر كفاءة مع عدم التشويش والضجيج» — تغيير صفحة فقط، بقية 1.9 حرفيًا.
# لا إذن إنترنت في أي إصدار — البلوتوث ليس إنترنت.
# درس إلزامي من ناسخ الكلمات: MainActivity.java يُعاد كتابته هنا داخل السكربت (heredoc) — أي تعديل عليه يكون هنا.
set -e
exec > >(tee -a "$HOME/workspace/voice-translator/android/build.log") 2>&1
echo "=== VOICE TRANSLATOR BUILD (APK 1.13) START $(date) ==="

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
OUT="$HOME/workspace/voice-translator/voice-translator-1.13.apk"

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

# ---------- أصول السمع الأصلي (1.4 — خارج www أيضًا) ----------
# Whisper-small بصيغة sherpa الرسمية (int8) من مرآة k2-fsa على HF
# (csukuangfj/sherpa-onnx-whisper-small) — البصمات موثّقة في BUILD.md §1.4.
rm -rf assets/asr
mkdir -p assets/asr/whisper-small
cp "$BUNDLE/whisper-small-sherpa/small-encoder.int8.onnx" \
   "$BUNDLE/whisper-small-sherpa/small-decoder.int8.onnx" \
   "$BUNDLE/whisper-small-sherpa/small-tokens.txt" assets/asr/whisper-small/
# (1.7) لا أصول لأذن 1.6 التجريبية في الحزمة إطلاقًا — أُزيلت ملفاتها
# (~1.04GB) من الـAPK بقرار Hilal؛ الأذن الأصلية الوحيدة هي small أعلاه.
du -sh assets assets/www assets/tts assets/asr

# ---------- البيان والموارد ----------
cat > AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.hilalsameer.voice"
    android:versionCode="14" android:versionName="1.13">
  <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="34"/>
  <uses-permission android:name="android.permission.RECORD_AUDIO"/>
  <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
  <!-- بلوتوث المرحلة الثانية (1.8): كلاسيك RFCOMM بين هاتفين، بلا إنترنت -->
  <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
  <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
  <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
  <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
  <uses-feature android:name="android.hardware.bluetooth" android:required="false"/>
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
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothServerSocket;
import android.bluetooth.BluetoothSocket;
import android.content.BroadcastReceiver;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.net.Uri;
import android.os.Bundle;
import android.util.Base64;
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
import com.k2fsa.sherpa.onnx.FeatureConfig;
import com.k2fsa.sherpa.onnx.GeneratedAudio;
import com.k2fsa.sherpa.onnx.OfflineModelConfig;
import com.k2fsa.sherpa.onnx.OfflineRecognizer;
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig;
import com.k2fsa.sherpa.onnx.OfflineStream;
import com.k2fsa.sherpa.onnx.OfflineTts;
import com.k2fsa.sherpa.onnx.OfflineWhisperModelConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig;
import java.io.EOFException;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONArray;
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
    // تسخين السمع الأصلي في الخلفية (1.4): استخراج ملفات
    // Whisper بصيغة sherpa وبناء المعرّف، كي تكون الأذن جاهزة
    // عند أول تسجيل.
    new Thread(() -> {
      try { bridge.warmAsr(); } catch (Throwable ignored) {}
    }).start();
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
    if (req == VoiceBridge.BT_REQ && bridge != null) {
      boolean all = results.length > 0;
      for (int r : results) if (r != PackageManager.PERMISSION_GRANTED) all = false;
      bridge.onBtPermsResult(all && bridge.btPermsOk());
    }
  }

  void evalTtsCallback(int id, boolean ok, String err) {
    evalTtsCallback(id, ok, err, null);
  }

  // ردّ نداء النطق مع الصوت الذي نطق فعلًا (1.5): يمرَّر معرّف الصوت الخادم
  // إلى الصفحة فتعرضه في سطر «الصوت المستعمل» داخل مربع الطرف صاحب الصوت —
  // دليل من الجهاز نفسه على أي نموذج نطق العبارة، لا مجرد ما اختير في القائمة.
  void evalTtsCallback(int id, boolean ok, String err, String voice) {
    String js = "window.__ttsCallback && window.__ttsCallback(" + id + "," + ok + ","
        + JSONObject.quote(err == null ? "" : err) + ","
        + (voice == null ? "null" : JSONObject.quote(voice)) + ")";
    w.evaluateJavascript(js, null);
  }

  // ردّ نداء السمع الأصلي (1.4): الحمولة هي النص المتعرّف عليه عند النجاح
  // أو رسالة الخطأ عند الفشل (عندها تسقط الصفحة إلى عامل الويب تلقائيًا).
  void evalAsrCallback(int id, boolean ok, String payload) {
    String js = "window.__asrCallback && window.__asrCallback(" + id + "," + ok + ","
        + JSONObject.quote(payload == null ? "" : payload) + ")";
    w.evaluateJavascript(js, null);
  }

  @Override public void onBackPressed() {
    if (w != null && w.canGoBack()) w.goBack(); else super.onBackPressed();
  }

  @Override protected void onDestroy() {
    if (bridge != null) { bridge.shutdownBt(); bridge.shutdownSysTts(); }
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
    // السمع الأصلي (1.4، وتركيبة 1.7): معرّف OfflineRecognizer واحد بصيغة
    // sherpa (int8) بلا عامل ويب — Whisper-small هي الأذن الأصلية الأساسية
    // والوحيدة كما في 1.4/1.5 (أُزيلت أذن 1.6 التجريبية في 1.7 بحكم Hilal
    // التجريبي على هاتفه: فضّل small في الاستعمال الحقيقي). اللغة تُفرض
    // لكل طلب عبر setConfig (يقرأها فكّاك whisper من إعداداته عند كل فكّ
    // ويعيد كتابة رمز اللغة الابتدائي)، فلا إعادة بناء عند تبديل اللغات.
    private OfflineRecognizer asr;
    private File asrEnc, asrDec, asrTokens;
    private String asrLang; // لغة الإعداد الحالي لمعرّف small
    private final Object asrLock = new Object();
    private volatile int asrState = 0; // small: 0 لم يُبنَ بعد، 1 جاهز، ‎-1 فشل نهائي
    private volatile String asrLastKind = ""; // الأذن التي خدمت آخر طلب فعلًا: small
    // بلوتوث المرحلة الثانية (1.8): RFCOMM كلاسيك بين هاتفين — خادم يستمع
    // وعميل يتصل، واتصال واحد قائم في أي وقت. الحالة تُبثّ للصفحة عبر
    // __btEvent، وكل فشل يظهر نصًا في واجهة الصفحة لا يُبتلع صامتًا.
    static final int BT_REQ = 2002;
    private static final int BT_DISC_REQ = 2003;
    private static final UUID BT_UUID = UUID.fromString("e8d5f1a0-7c3b-4a2e-9f6d-1b0c8a7e5d42");
    private static final String BT_SVC_NAME = "VoiceTranslator";
    private volatile String btState = "off"; // off|listening|connecting|connected|disconnected
    private volatile String btPeer = "";
    private volatile boolean btServerOn = false;
    private volatile boolean btIsServerConn = false;
    private BluetoothServerSocket btServer;
    private BluetoothSocket btSocket;
    private OutputStream btOut;
    private final Object btWriteLock = new Object();
    private BroadcastReceiver btDiscoveryReceiver;
    private final ExecutorService btSendExec = Executors.newSingleThreadExecutor();

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
      runOnUiThread(() -> evalTtsCallback(cbId, fok, ferr, voice));
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
      runOnUiThread(() -> evalTtsCallback(fcb, ok, err, "ar-system"));
    }

    void shutdownSysTts() {
      if (sysTts != null) {
        try { sysTts.stop(); sysTts.shutdown(); } catch (Throwable ignored) {}
        sysTts = null;
      }
    }

    /* ===== بلوتوث المرحلة الثانية (1.8) — هاتفان عبر RFCOMM =====
       التصميم المعتمد (SPEC بند 6): الترجمة تُحسب على هاتف المرسل بسلسلته
       القائمة، وما يعبر البلوتوث حزمة واحدة مؤطّرة (4 بايت طول بادئ كبير
       الطرف + JSON UTF-8): النص الأصلي المسموع + النص المترجم + اللغتان +
       مقطع صوت المتكلم الأصلي اختياريًا (PCM16 خام 16kHz بـBase64 — تسجيل
       الصفحة نفسه). المستقبِل يعرض النصين وينطق الترجمة بصوته وإعداداته هو
       عبر مسارَي النطق القائمين، وزر يعيد تشغيل صوت المرسل الحقيقي كما هو
       (playAudioClip أدناه). الحزم الكبيرة تُقرأ كاملة قبل التسليم — لا
       تسليم جزئي أبدًا (BtFrame يقرأ الإطار كاملًا أو يرمي). */

    // بثّ حدث بلوتوث إلى الصفحة (حالة/خطأ/جهاز مكتشف/عبارة واردة/أذونات)
    private void btEmit(JSONObject ev) {
      final String s = ev.toString();
      runOnUiThread(() -> {
        try { w.evaluateJavascript("window.__btEvent && window.__btEvent(" + JSONObject.quote(s) + ")", null); }
        catch (Throwable ignored) {}
      });
    }

    private void btStatus(String state, String peer) {
      btState = state;
      btPeer = peer == null ? "" : peer;
      try {
        JSONObject ev = new JSONObject();
        ev.put("kind", "status");
        ev.put("state", state);
        ev.put("peer", btPeer);
        ev.put("listening", btServerOn);
        btEmit(ev);
      } catch (Throwable ignored) {}
      Log.i(TAG, "bt status=" + state + " peer=" + btPeer + " listening=" + btServerOn);
    }

    private void btError(String msg) {
      Log.w(TAG, "bt error: " + msg);
      try {
        JSONObject ev = new JSONObject();
        ev.put("kind", "error");
        ev.put("message", msg);
        btEmit(ev);
      } catch (Throwable ignored) {}
    }

    private BluetoothAdapter btAdapter() {
      try {
        BluetoothManager bm = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
        if (bm != null && bm.getAdapter() != null) return bm.getAdapter();
      } catch (Throwable ignored) {}
      try { return BluetoothAdapter.getDefaultAdapter(); } catch (Throwable e) { return null; }
    }

    // الأذونات الناقصة بحسب جيل النظام: 12+ ‏CONNECT/SCAN، وما قبله موقع
    // دقيق (شرط اكتشاف الأجهزة في الأجيال القديمة). تُطلب وقت الاستعمال فقط.
    private String[] btMissingPerms() {
      ArrayList<String> need = new ArrayList<>();
      try {
        if (android.os.Build.VERSION.SDK_INT >= 31) {
          if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED)
            need.add(Manifest.permission.BLUETOOTH_CONNECT);
          if (checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED)
            need.add(Manifest.permission.BLUETOOTH_SCAN);
        } else {
          if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED)
            need.add(Manifest.permission.ACCESS_FINE_LOCATION);
        }
      } catch (Throwable ignored) {}
      return need.toArray(new String[0]);
    }

    @JavascriptInterface public boolean btPermsOk() { return btMissingPerms().length == 0; }

    @JavascriptInterface public void btRequestPerms() {
      final String[] need = btMissingPerms();
      if (need.length == 0) { onBtPermsResult(true); return; }
      runOnUiThread(() -> {
        try { requestPermissions(need, BT_REQ); }
        catch (Throwable e) { onBtPermsResult(false); }
      });
    }

    void onBtPermsResult(boolean granted) {
      try {
        JSONObject ev = new JSONObject();
        ev.put("kind", "perms");
        ev.put("granted", granted);
        btEmit(ev);
      } catch (Throwable ignored) {}
    }

    // فحوص مشتركة قبل أي عملية: محوّل موجود ومفعّل والأذونات حاضرة —
    // كل غياب يظهر رسالة واضحة في الواجهة، لا انهيار ولا صمت.
    private BluetoothAdapter btReady() {
      BluetoothAdapter ad = btAdapter();
      if (ad == null) { btError("هذا الجهاز بلا بلوتوث"); return null; }
      if (!ad.isEnabled()) { btError("البلوتوث غير مفعّل — فعّله من إعدادات الهاتف ثم أعد المحاولة"); return null; }
      if (!btPermsOk()) { btError("إذن البلوتوث مفقود — امنحه من إعدادات التطبيق"); return null; }
      return ad;
    }

    // جعل الهاتف قابلًا للاكتشاف مؤقتًا عند بدء الاستقبال (حوار نظامي
    // يوافق عليه المستخدم) كي يجده هاتف الطرف الآخر في أول اقتران.
    private void btEnsureDiscoverable(BluetoothAdapter ad) {
      try {
        if (ad.getScanMode() != BluetoothAdapter.SCAN_MODE_CONNECTABLE_DISCOVERABLE) {
          Intent i = new Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE);
          i.putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300);
          startActivityForResult(i, BT_DISC_REQ);
        }
      } catch (Throwable ignored) {}
    }

    /* ----- الخادم: يستمع ويقبل اتصالًا واحدًا، ويعود للاستماع بعد انقطاعه ----- */
    @JavascriptInterface public void btStartServer() {
      new Thread(() -> {
        BluetoothAdapter ad = btReady();
        if (ad == null) return;
        if (btServerOn) { btStatus("listening", ""); return; }
        try {
          btServer = ad.listenUsingRfcommWithServiceRecord(BT_SVC_NAME, BT_UUID);
        } catch (Throwable e) {
          btError("تعذّر بدء الاستقبال: " + e.getMessage());
          return;
        }
        btServerOn = true;
        btEnsureDiscoverable(ad);
        btStatus("listening", "");
        while (btServerOn) {
          BluetoothSocket s;
          try { s = btServer.accept(); }
          catch (Throwable e) {
            if (btServerOn) btError("توقّف الاستقبال: " + e.getMessage());
            break;
          }
          if (s != null) handleBtConnected(s, true);
        }
      }).start();
    }

    /* ----- العميل: اتصال بجهاز مختار بعنوانه ----- */
    @JavascriptInterface public void btConnect(final String address) {
      new Thread(() -> {
        BluetoothAdapter ad = btReady();
        if (ad == null) return;
        btStatus("connecting", address);
        BluetoothSocket s = null;
        try {
          try { ad.cancelDiscovery(); } catch (Throwable ignored) {}
          BluetoothDevice dev = ad.getRemoteDevice(address);
          s = dev.createRfcommSocketToServiceRecord(BT_UUID);
          s.connect();
        } catch (Throwable e) {
          if (s != null) { try { s.close(); } catch (Throwable ignored) {} }
          btError("تعذّر الاتصال بالهاتف الآخر — تأكد أنه يستمع في التطبيق نفسه: " + e.getMessage());
          btStatus(btServerOn ? "listening" : "off", "");
          return;
        }
        handleBtConnected(s, false);
      }).start();
    }

    // تثبيت اتصال قائم وبدء خيط قراءته. اتصال ثانٍ وارد أثناء قيام واحد
    // يُغلق فورًا — اتصال واحد في أي وقت كما صُمم.
    private void handleBtConnected(BluetoothSocket s, boolean serverSide) {
      final InputStream in;
      synchronized (btWriteLock) {
        if (btSocket != null) {
          try { s.close(); } catch (Throwable ignored) {}
          return;
        }
        try {
          btOut = s.getOutputStream();
          in = s.getInputStream();
          btSocket = s;
          btIsServerConn = serverSide;
        } catch (Throwable e) {
          try { s.close(); } catch (Throwable ignored) {}
          btError("تعذّر فتح قناة الاتصال: " + e.getMessage());
          return;
        }
      }
      String peer = "";
      try {
        BluetoothDevice d = s.getRemoteDevice();
        String nm = null;
        try { nm = d.getName(); } catch (Throwable ignored) {}
        peer = (nm != null && !nm.isEmpty()) ? nm : d.getAddress();
      } catch (Throwable ignored) {}
      btStatus("connected", peer);
      new Thread(() -> {
        try {
          byte[] frame;
          while ((frame = BtFrame.readFrame(in)) != null) deliverBtFrame(frame);
        } catch (Throwable e) {
          Log.i(TAG, "bt read ended: " + e);
        }
        btConnectionLost();
      }).start();
    }

    // تسليم حزمة واردة كاملة إلى الصفحة بعد التحقق أنها عبارة ببنيتها
    private void deliverBtFrame(byte[] frame) {
      try {
        String text = new String(frame, "UTF-8");
        JSONObject pkt = new JSONObject(text);
        if (!"utterance".equals(pkt.optString("type"))) {
          Log.w(TAG, "bt frame ignored, type=" + pkt.optString("type"));
          return;
        }
        JSONObject ev = new JSONObject();
        ev.put("kind", "utterance");
        ev.put("packet", pkt);
        btEmit(ev);
        Log.i(TAG, "bt utterance delivered heard=" + pkt.optString("heardText").length()
            + " tr=" + pkt.optString("translatedText").length()
            + " audio=" + (pkt.has("audioB64") ? "yes" : "no"));
      } catch (Throwable e) {
        btError("وصلت حزمة تالفة عبر البلوتوث وتُجاهلت");
      }
    }

    // انقطاع الاتصال القائم: تنظيف الحقول وإعلان الحالة (يعود الخادم
    // للاستماع تلقائيًا إن كان مفعّلًا — حلقة القبول قائمة أصلًا)
    private void btConnectionLost() {
      synchronized (btWriteLock) {
        if (btSocket != null) { try { btSocket.close(); } catch (Throwable ignored) {} }
        btSocket = null;
        btOut = null;
      }
      if (!"off".equals(btState)) btStatus("disconnected", "");
    }

    /* ----- الإرسال: إطار كامل على خيط إرسال مخصص فلا يحظر خيط الجسر ----- */
    @JavascriptInterface public void btSend(final String json) {
      btSendExec.execute(() -> {
        OutputStream out;
        synchronized (btWriteLock) { out = btOut; }
        if (out == null) { btError("لا اتصال بلوتوث قائم — اتصل أولًا"); return; }
        try {
          byte[] payload = json.getBytes("UTF-8");
          synchronized (btWriteLock) { BtFrame.writeFrame(out, payload); }
          Log.i(TAG, "bt sent bytes=" + payload.length);
        } catch (Throwable e) {
          btError("فشل الإرسال عبر البلوتوث: " + e.getMessage());
          btConnectionLost();
        }
      });
    }

    /* ----- قائمة المقترنة والاكتشاف ----- */
    @JavascriptInterface public String btListPaired() {
      JSONArray arr = new JSONArray();
      try {
        BluetoothAdapter ad = btAdapter();
        if (ad != null) {
          for (BluetoothDevice d : ad.getBondedDevices()) {
            JSONObject o = new JSONObject();
            String nm = null;
            try { nm = d.getName(); } catch (Throwable ignored) {}
            o.put("name", nm == null ? "" : nm);
            o.put("address", d.getAddress());
            arr.put(o);
          }
        }
      } catch (Throwable e) {
        Log.w(TAG, "bt paired list failed", e);
      }
      return arr.toString();
    }

    @JavascriptInterface public void btStartDiscovery() {
      BluetoothAdapter ad = btReady();
      if (ad == null) return;
      try {
        if (btDiscoveryReceiver == null) {
          btDiscoveryReceiver = new BroadcastReceiver() {
            @Override public void onReceive(Context c, Intent intent) {
              String a = intent.getAction();
              if (BluetoothDevice.ACTION_FOUND.equals(a)) {
                try {
                  BluetoothDevice d = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                  if (d == null) return;
                  String nm = null;
                  try { nm = d.getName(); } catch (Throwable ignored) {}
                  JSONObject ev = new JSONObject();
                  ev.put("kind", "device");
                  ev.put("name", nm == null ? "" : nm);
                  ev.put("address", d.getAddress());
                  btEmit(ev);
                } catch (Throwable ignored) {}
              } else if (BluetoothAdapter.ACTION_DISCOVERY_FINISHED.equals(a)) {
                try {
                  JSONObject ev = new JSONObject();
                  ev.put("kind", "discoveryDone");
                  btEmit(ev);
                } catch (Throwable ignored) {}
              }
            }
          };
          IntentFilter f = new IntentFilter();
          f.addAction(BluetoothDevice.ACTION_FOUND);
          f.addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED);
          registerReceiver(btDiscoveryReceiver, f);
        }
        if (ad.isDiscovering()) ad.cancelDiscovery();
        if (ad.startDiscovery()) {
          JSONObject ev = new JSONObject();
          ev.put("kind", "discovering");
          btEmit(ev);
        } else {
          btError("تعذّر بدء البحث عن أجهزة");
        }
      } catch (Throwable e) {
        btError("تعذّر البحث عن أجهزة: " + e.getMessage());
      }
    }

    /* ----- قطع كل شيء: الاتصال والاستماع والاكتشاف ----- */
    @JavascriptInterface public void btDisconnect() {
      btServerOn = false;
      if (btServer != null) { try { btServer.close(); } catch (Throwable ignored) {} btServer = null; }
      synchronized (btWriteLock) {
        if (btSocket != null) { try { btSocket.close(); } catch (Throwable ignored) {} }
        btSocket = null;
        btOut = null;
      }
      try {
        BluetoothAdapter ad = btAdapter();
        if (ad != null && ad.isDiscovering()) ad.cancelDiscovery();
      } catch (Throwable ignored) {}
      btStatus("off", "");
    }

    void shutdownBt() {
      try { btDisconnect(); } catch (Throwable ignored) {}
      if (btDiscoveryReceiver != null) {
        try { unregisterReceiver(btDiscoveryReceiver); } catch (Throwable ignored) {}
        btDiscoveryReceiver = null;
      }
    }

    /* ----- تشغيل مقطع صوت حقيقي وارد (1.8) -----
       يعيد تشغيل PCM المرسل (16kHz أحادي PCM16 بـBase64 — تسجيل الصفحة
       نفسه) كما هو عبر playSamples، فيسمع المستقبِل صوت المتكلم الأصلي
       لا صوتًا مولّدًا. الردّ بآلية نداء النطق نفسها (بلا صوت مولّد). */
    @JavascriptInterface public void playAudioClip(final String b64, final int cbId) {
      boolean ok = false;
      String err = "";
      try {
        byte[] pcm = Base64.decode(b64, Base64.DEFAULT);
        float[] samples = new float[pcm.length / 2];
        for (int i = 0; i < samples.length; i++) {
          int v = (pcm[2 * i] & 0xff) | (pcm[2 * i + 1] << 8);
          samples[i] = ((short) v) / 32768f;
        }
        stopFlag = false;
        playSamples(samples, 16000);
        ok = true;
      } catch (Throwable e) {
        err = String.valueOf(e);
        Log.e(TAG, "playAudioClip failed", e instanceof Exception ? (Exception) e : new Exception(e));
      }
      final boolean fok = ok;
      final String ferr = err;
      runOnUiThread(() -> evalTtsCallback(cbId, fok, ferr, null));
    }

    /* ===== السمع الأصلي (1.4) — تركيبة 1.7 =====
       الصفحة ترسل PCM 16kHz (PCM16 بـBase64) من مسار التسجيل القائم نفسه،
       فيتعرّف عليه المعرّف الأصلي هنا. سلسلة السقوط كما في 1.4/1.5:
       Whisper-small أصليًا أولًا، فإن فشل بناؤه أو فكّه ردّ النداء خطأً
       للصفحة فتسقط تلقائيًا إلى عامل الويب القديم الذي يبقى في الحزمة كما
       هو — لا تعطّل كامل أبدًا. فشل البناء نهائي ويُعلَّم (state=-1) فلا
       تُفضَّل الأذن بعده، وسطر السجل يوثّق المسار الخادم لكل طلب.
       (أُزيلت أذن 1.6 التجريبية من هذه التركيبة كليًا — ملفات وجسرًا —
       بحكم Hilal بعد تجربته على هاتفه: 1.4 بأذنها small أفضل عنده.) */

    // تسخين عند إقلاع التطبيق (خيط خلفي من onCreate): بناء أذن small
    // الأصلية كي تكون جاهزة عند أول تسجيل.
    void warmAsr() {
      synchronized (asrLock) {
        try { ensureAsrLocked(); }
        catch (Throwable e) { Log.e(TAG, "asr small warm failed", e); }
      }
    }

    // للصفحة: هل توجد أذن أصلية جاهزة؟ (تُفضّلها الصفحة وتسقط للويب عند غيابها)
    @JavascriptInterface public boolean asrNativeAvailable() {
      return asrState == 1;
    }

    // للصفحة (شارة 1.6 الصادقة، بتركيبة 1.7): اسم الأذن الأصلية الجاهزة
    // فعلًا — "small" حين تجهز، وسلسلة فارغة عند غيابها (عامل الويب هو
    // الخادم حينها). شارة حالة السمع في الصفحة تعرض هذا الاسم كما هو،
    // فلا تدّعي أذنًا غير التي تخدم.
    @JavascriptInterface public String asrNativeKind() {
      if (asrState == 1) return "small";
      return "";
    }

    // للصفحة (1.6، بتركيبة 1.7): الأذن التي خدمت آخر طلب سمع فعلًا —
    // توثّقها الصفحة في سطر وحدة التحكم لكل طلب.
    @JavascriptInterface public String asrLastServedKind() {
      return asrLastKind;
    }

    // تعرّف أصلي: يعمل على خيط الجسر ويحظر حتى الاكتمال (نمط speak نفسه)،
    // ثم يردّ النداء للصفحة بالنص أو بالخطأ. سطر السجل يوثّق المسار الخادم.
    @JavascriptInterface public void transcribeNative(final String b64, final String lang, final int cbId) {
      boolean ok = false;
      String payload = "";
      String served = "";
      long t0 = System.currentTimeMillis();
      int sampleCount = 0;
      try {
        byte[] pcm = Base64.decode(b64, Base64.DEFAULT);
        float[] samples = new float[pcm.length / 2];
        for (int i = 0; i < samples.length; i++) {
          int v = (pcm[2 * i] & 0xff) | (pcm[2 * i + 1] << 8);
          samples[i] = ((short) v) / 32768f;
        }
        sampleCount = samples.length;
        synchronized (asrLock) {
          ensureAsrLocked();
          asrLang = applyAsrLang(asr, asrEnc, asrDec, asrTokens, asrLang, lang);
          payload = decodeChunkedLocked(asr, samples);
          served = "small";
        }
        asrLastKind = served;
        ok = true;
      } catch (Throwable e) {
        payload = String.valueOf(e);
        Log.e(TAG, "asr native failed", e instanceof Exception ? (Exception) e : new Exception(e));
      }
      Log.i(TAG, "asr path=" + (served.isEmpty() ? "native-failed" : served)
          + " lang=" + lang + " ok=" + ok + " samples=" + sampleCount
          + " ms=" + (System.currentTimeMillis() - t0));
      final boolean fok = ok;
      final String fpayload = payload;
      runOnUiThread(() -> evalAsrCallback(cbId, fok, fpayload));
    }

    // بناء المعرّف عند الحاجة (داخل asrLock): استخراج موثّق بالحجم إلى جذر
    // جديد asr/v14 ثم بناء الجلسات بلغة ابتدائية (العربية — لغة الطرف أ).
    private void ensureAsrLocked() throws Exception {
      if (asr != null) return;
      if (asrState == -1) throw new Exception("native asr unavailable (earlier failure)");
      File dir = new File(new File(getFilesDir(), "asr"), "v14/whisper-small");
      if (!dir.isDirectory()) dir.mkdirs();
      asrEnc = new File(dir, "small-encoder.int8.onnx");
      asrDec = new File(dir, "small-decoder.int8.onnx");
      asrTokens = new File(dir, "small-tokens.txt");
      try {
        extractVerified("asr/whisper-small/small-encoder.int8.onnx", asrEnc);
        extractVerified("asr/whisper-small/small-decoder.int8.onnx", asrDec);
        extractVerified("asr/whisper-small/small-tokens.txt", asrTokens);
        asr = new OfflineRecognizer(null, buildAsrConfig(asrEnc, asrDec, asrTokens, "ar"));
      } catch (Throwable e) {
        asrState = -1; // فشل نهائي: لا تُفضّل الصفحة هذا المسار بعد الآن
        throw e instanceof Exception ? (Exception) e : new Exception(e);
      }
      asrLang = "ar";
      asrState = 1;
      Log.i(TAG, "asr small built enc=" + asrEnc.length() + " dec=" + asrDec.length());
    }

    // إعداد معرّف whisper لأذن small — بناء الإعداد (1.4).
    // ملاحظة featureDim=80: محرك whisper في sherpa يقرأ n_mels من بيانات
    // النموذج الوصفية نفسها.
    private OfflineRecognizerConfig buildAsrConfig(File enc, File dec, File tokens, String lang) {
      OfflineWhisperModelConfig wcfg = new OfflineWhisperModelConfig();
      wcfg.setEncoder(enc.getAbsolutePath());
      wcfg.setDecoder(dec.getAbsolutePath());
      wcfg.setLanguage(lang);
      wcfg.setTask("transcribe");
      OfflineModelConfig mcfg = new OfflineModelConfig();
      mcfg.setWhisper(wcfg);
      mcfg.setTokens(tokens.getAbsolutePath());
      mcfg.setNumThreads(4);
      mcfg.setDebug(false);
      mcfg.setProvider("cpu");
      FeatureConfig fcfg = new FeatureConfig();
      fcfg.setSampleRate(16000);
      fcfg.setFeatureDim(80);
      OfflineRecognizerConfig rcfg = new OfflineRecognizerConfig();
      rcfg.setFeatConfig(fcfg);
      rcfg.setModelConfig(mcfg);
      rcfg.setDecodingMethod("greedy_search");
      return rcfg;
    }

    // فرض لغة الطلب على معرّف بعينه (داخل asrLock): setConfig تُحدّث إعداد
    // whisper داخل المحرك، وفكّاكه يقرأ اللغة من إعداداته عند كل فكّ —
    // فلا إعادة بناء. تعيد لغة الإعداد الجديدة لتُحفظ في حقل الأذن.
    private String applyAsrLang(OfflineRecognizer rec, File enc, File dec, File tokens, String cur, String lang) {
      if (lang == null || lang.equals(cur)) return cur;
      rec.setConfig(buildAsrConfig(enc, dec, tokens, lang));
      Log.i(TAG, "asr language set to " + lang);
      return lang;
    }

    // فكّ الصوت بمعرّف بعينه (داخل asrLock). حدّ محرك whisper في sherpa:
    // أول ~29.5 ثانية فقط من أي دفقة واحدة — فنقطع التسجيل (سقفه 45 ثانية
    // أصلًا) إلى قطع 25 ثانية متتالية ونفكّ كلًّا وحدها ثم نصل النصوص.
    private String decodeChunkedLocked(OfflineRecognizer rec, float[] samples) throws Exception {
      final int CHUNK = 25 * 16000;
      StringBuilder out = new StringBuilder();
      for (int off = 0; off < samples.length; off += CHUNK) {
        int n = Math.min(CHUNK, samples.length - off);
        float[] part = new float[n];
        System.arraycopy(samples, off, part, 0, n);
        OfflineStream stream = rec.createStream();
        try {
          stream.acceptWaveform(part, 16000);
          rec.decode(stream);
          String text = rec.getResult(stream).getText();
          if (text != null) {
            text = text.trim();
            if (!text.isEmpty()) {
              if (out.length() > 0) out.append(' ');
              out.append(text);
            }
          }
        } finally {
          try { stream.release(); } catch (Throwable ignored) {}
        }
      }
      return out.toString();
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

/* تأطير حزم البلوتوث (1.8): إطار = 4 بايت طول بادئ (big-endian) + حمولة.
   صنف نقي بلا أي اعتماد على أندرويد — يُختبر منطقيًا على JVM سطح مكتب
   (كتابة/قراءة round-trip عبر تيارات ذاكرة). القراءة إما أن تعيد الإطار
   كاملًا أو ترمي — لا تسليم جزئي أبدًا؛ ونهاية تيار نظيفة عند حدّ إطار
   تعيد null (انقطاع مهذّب). سقف الحجم يحمي من طول تالف/خبيث. */
class BtFrame {
  static final int MAX_FRAME = 64 * 1024 * 1024;

  static void writeFrame(OutputStream out, byte[] payload) throws IOException {
    int n = payload.length;
    if (n > MAX_FRAME) throw new IOException("frame too large: " + n);
    out.write((n >>> 24) & 0xff);
    out.write((n >>> 16) & 0xff);
    out.write((n >>> 8) & 0xff);
    out.write(n & 0xff);
    out.write(payload);
    out.flush();
  }

  static byte[] readFrame(InputStream in) throws IOException {
    int b0 = in.read();
    if (b0 < 0) return null; // نهاية نظيفة عند حدّ إطار
    int b1 = readByteOrThrow(in);
    int b2 = readByteOrThrow(in);
    int b3 = readByteOrThrow(in);
    int n = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
    if (n < 0 || n > MAX_FRAME) throw new IOException("bad frame length: " + n);
    byte[] buf = new byte[n];
    int off = 0;
    while (off < n) {
      int r = in.read(buf, off, n - off);
      if (r < 0) throw new EOFException("frame truncated at " + off + "/" + n);
      off += r;
    }
    return buf;
  }

  private static int readByteOrThrow(InputStream in) throws IOException {
    int b = in.read();
    if (b < 0) throw new EOFException("eof inside frame header");
    return b;
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
