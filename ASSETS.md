# جرد أصول «المترجم الصوتي دون اتصال» — المرحلة أ (2026-11-22)

حزمة الأصول في `assets-bundle/` — كل ما سيدخل الـAPK من نماذج وبيانات.
**الحجم الكلي للحزمة: 1,627,971,980 بايت ≈ 1.52 GiB** (409 ملفات).

## ١) السمع — whisper-small/ (251,877,510 بايت)

| الملف | الحجم (بايت) | الغرض | الإثبات |
|---|---|---|---|
| onnx/encoder_model_quantized.onnx | 92,324,809 | مشفّر Whisper-small (int8) | مُثبت في voice-test: CER عربي 9.5% / إنجليزي 0% / هندي 22.5% / أردي 5.6% على عيّنات نظيفة |
| onnx/decoder_model_merged_quantized.onnx | 156,780,950 | مفكّك Whisper-small (int8) | كسابقه |
| tokenizer.json | 2,480,466 | مُرمّز Whisper | — |
| tokenizer_config.json | 282,683 | إعداد المُرمّز | — |
| config.json | 2,232 | إعداد النموذج | — |
| generation_config.json | 3,837 | إعداد التوليد | — |
| preprocessor_config.json | 339 | إعداد المعالجة الصوتية | — |
| special_tokens_map.json | 2,194 | رموز خاصة | — |

## ٢) الترجمة — nllb-200-distilled-600M/ (911,962,632 بايت)

| الملف | الحجم (بايت) | الغرض | الإثبات |
|---|---|---|---|
| onnx/encoder_model_quantized.onnx | 419,120,483 | مشفّر NLLB (int8) | مُثبت في voice-test: 30 ترجمة/10 اتجاهات سليمة عدا تحية الأردية |
| onnx/decoder_model_merged_quantized.onnx | 475,505,771 | مفكّك NLLB (int8) | كسابقه + أزواج العربية التكميلية (hi→ar مطابق، ar→ur سليم، ur→ar عدا التحية) |
| tokenizer.json | 17,331,224 | مُرمّز SentencePiece | — |
| special_tokens_map.json | 3,548 | رموز اللغات | — |
| config.json | 873 | إعداد النموذج | — |
| tokenizer_config.json | 544 | إعداد المُرمّز | — |
| generation_config.json | 189 | إعداد التوليد | — |

## ٣) النطق — piper-voices/ (445,046,541 بايت)

كل صوت: ملف .onnx **مُرقّع ببيانات sherpa الوصفية** (model_type=vits, comment=piper, language, voice=قيمة espeak من إعداد الصوت نفسه, has_espeak=1, n_speakers, sample_rate) — النماذج الخام من rhasspy/piper-voices بلا بيانات وصفية ويرفضها sherpa-onnx؛ الرقعة هي نفس تحويلة مكتبة sherpa الرسمية (تحققنا منها بمطابقة tokens.txt لـlessac بايتًا ببايت وبفحص بيانات نسخة المكتبة). وملف .onnx.json الأصلي، وملف .tokens.txt مولّد من phoneme_id_map (للأصوات ryan/fasih/aegis حُذفت 5 رموز ثنائية المقطع aɪ/aʊ/ɔɪ/eɪ/oʊ لأن قارئ رموز sherpa يقبل الرموز أحادية المقطع فقط — وهي لا تُنتَج منفردة من espeak أصلًا).

| الصوت | اللغة/الجنس | .onnx (بايت) | إثبات sherpa (جملة المستشفى) |
|---|---|---|---|
| ar_JO-kareem-medium | عربي — ذكر (الصوت العربي الوحيد في Piper) | 63,201,421 | ✅ 3.12s، ذروة 0.495 |
| en_US-lessac-medium | إنجليزي — أنثى | 63,201,425 | ✅ 2.07s، ذروة 0.484 |
| en_US-ryan-medium | إنجليزي — ذكر | 63,222,115 | ✅ 1.71s، ذروة 0.541 |
| hi_IN-priyamvada-medium | هندي — أنثى | 63,516,176 | ✅ 2.81s، ذروة 0.737 |
| hi_IN-pratham-medium | هندي — ذكر (نُزّل في هذه المرحلة) | 63,516,176 | ✅ 2.16s، ذروة 0.712 |
| ur_PK-aegis_female-medium | أردي — أنثى | 63,515,714 | ✅ 2.69s، ذروة 0.881 |
| ur_PK-fasih-medium | أردي — ذكر (نُزّل في هذه المرحلة من أول محاولة، 64,832,023 بايت خام) | 64,832,148 | ✅ 2.15s، ذروة 0.972 |

ملفات .onnx.json المرافقة: 3,237–6,382 بايت لكل صوت؛ ملفات .tokens.txt: 921–968 بايت لكل صوت.
**إثبات sherpa كامل: 7/7** عبر sherpa-onnx 1.12.40 (OfflineTts/VITS) على الخادم — العيّنات في `sherpa-proof/` بصيغتي wav وmp3.

## ٤) بيانات espeak-ng — espeak-ng-data/ (19,085,297 بايت، 373 ملفًا)

بيانات مُحوّل الصوتيات الذي تعتمد عليه أصوات Piper كلها (phoneme_type=espeak). المصدر: حزمة piper-tts من PyPI (المجلد piper/espeak-ng-data داخل الحزمة) — نفس البيانات التي استخدمها إثبات sherpa الناجح أعلاه. تشمل قواميس اللغات الأربع (ar_dict, hi_dict, ur_dict, en_dict) وجداول الصوتيات (phontab/phondata/phonindex) وأصوات lang (sem/ar, inc/hi, inc/ur, gmw/en-US).

## ٥) مكتبة الهاتف — sherpa-onnx AAR (ليست داخل الحزمة؛ تُدمج في الـAPK كمكتبة)

- **المصدر**: Maven Central لا يستضيف `com.k2fsa:sherpa-onnx` أصلًا (404 موثّق على repo1.maven.org وrepo.maven.apache.org؛ الموجود هناك إعادة تغليف طرف ثالث com.bihe0832.android لم تُستخدم). البديل الرسمي الوحيد المستخدم: إصدارات GitHub لـk2-fsa/sherpa-onnx.
- **الإصدار المختار: 1.12.40** (sherpa-onnx-1.12.40.aar — 56,480,361 بايت). نُزّل أيضًا الأحدث 2.0.2 (52,321,252 بايت) و**رُفض بسبب موثّق**: في ≥2.0.0 صار `--vits-data-dir` مهملًا ومُتجاهَلًا (تحذير صريح من المكتبة) وانكسر مسار Piper+espeak-ng-data الذي تقوم عليه الخطة؛ و1.12.40 هو أحدث خط 1.12 المستقر الذي يعمل بهذا المسار ومطابَق بحزمة Python التي نجح بها الإثبات.
- **مكتبات .so** (4 لكل معمارية × 4 معماريات: arm64-v8a, armeabi-v7a, x86, x86_64): libonnxruntime.so, libsherpa-onnx-jni.so, libsherpa-onnx-c-api.so, libsherpa-onnx-cxx-api.so. مجموع arm64-v8a وحده: 35,096,360 بايت.
- **كلاسات النطق الأساسية** (من classes.jar — 231,979 بايت): `com.k2fsa.sherpa.onnx.OfflineTts`, `OfflineTtsConfig`, `OfflineTtsModelConfig`, `OfflineTtsVitsModelConfig` (هي ما تستخدمه أصوات Piper)، و`TtsKt` (دالة getOfflineTtsConfig المساعدة). معامل سرعة النطق مدمج في مسار التوليد (GenerationConfig/speed في generate).

## الحجم المتوقع للـAPK

- الحزمة 1,627,971,980 + مكتبات arm64-v8a ‏(35,096,360) + classes.jar ‏(231,979) + كود التطبيق وموارده (صغير) ≈ **1.66 GB (≈1.55 GiB)** لبناء arm64 فقط، قبل ضغط ZIP في الـAPK (نماذج ONNX لا تنضغط كثيرًا — يُعتمد الرقم الخام للتخطيط).
- بناء بكل المعماريات الأربع يضيف ~107MB إضافية من الـ.so.
