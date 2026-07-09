/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState } from 'react';
import { 
  ShieldCheck, 
  MoveDown, 
  SlidersHorizontal, 
  Type, 
  Play, 
  Mic,
  CheckCircle2,
  Globe
} from 'lucide-react';

const content = {
  en: {
    navTitle: "Recite Quran",
    getApp: "Get the App",
    earlyAccess: "Early Access on Google Play",
    heroTitleEn: "Recite Quran",
    heroTitleAr: "اتلو القران",
    heroDesc: "Improve your recitation and memorization of The Great Quran. Records your voice and highlights the words on the screen as you recite—instantly.",
    getOn: "Get it on",
    googlePlay: "Google Play",
    tryWeb: "Try it without downloading",
    github: "Direct Download",
    watchVideo: "Watch how it works",
    about1: "Whether you are memorizing a new Surah or reviewing your daily Hifz, this app records your voice and highlights the words on the screen as you recite—instantly.",
    about2Part1: "Processes your voice entirely on your device. ",
    about2Highlight: "No internet connection is required",
    about2Part2: ", guaranteeing your complete privacy and ensuring you can practice anywhere, anytime.",
    forAllah: "\"For the sake of Allah\"",
    featuresTitle: "Powerful Features for Your Hifz",
    f1Title: "Real-Time Word Tracking",
    f1Desc: "Watch the words light up in green as you recite correctly, and instantly spot skipped or missed words marked in red.",
    f2Title: "100% Offline & Private",
    f2Desc: "Your voice never leaves your phone. All audio processing runs locally for total privacy and zero mobile data usage.",
    f3Title: "Smart Auto-Scroll",
    f3Desc: "The screen automatically scrolls to follow your recitation pace, allowing for a completely hands-free reading experience.",
    f4Title: "Tajweed & Tashkeel Checking",
    f4Desc: "Instantly highlights duration and vowel mistakes in yellow, helping you perfect your Tajweed rules like Madd and Ghunnah.",
    f5Title: "Voice Search Navigation",
    f5Desc: "Recite any verse into the microphone, and the app will instantly search the entire Quran and navigate you to it.",
    readyStart: "Ready to start?",
    experienceAi: "Experience it locally on your device.",
    downloadNow: "Download Now",
    screenTitle: "Beautifully Simple Interface",
    screenDesc: "Designed to minimize distractions while you focus on the Book of Allah.",
    screen1: "Reading View Screenshot",
    screen2: "Mistake Check Screenshot",
    screen3: "Settings Menu Screenshot",
    placeHere: "Place Here",
    privacyTitle: "Your Privacy, Guaranteed",
    privacyDesc: "No cloud syncing. No internet required. Process your recitation locally and practice with complete peace of mind.",
    availableNow: "Available now",
    footerDesc: "Improve your recitation and memorization of The Great Quran.",
    policy: "Privacy Policy",
    terms: "Terms of Service",
    contact: "Contact Support",
    rights: "WayOfTheSalaf. All rights reserved."
  },
  ar: {
    navTitle: "اتلو القران",
    getApp: "حمل التطبيق",
    earlyAccess: "وصول مبكر على جوجل بلاي",
    heroTitleEn: "اتلو القران",
    heroTitleAr: "Recite Quran",
    heroDesc: "حسّن تلاوتك وحفظك للقرآن العظيم. يسجل التطبيق صوتك ويحدد الكلمات على الشاشة أثناء التلاوة فوراً.",
    getOn: "احصل عليه من",
    googlePlay: "جوجل بلاي",
    tryWeb: "جربه بدون تحميل",
    github: "رابط مباشر",
    watchVideo: "شاهد كيف يعمل",
    about1: "سواء كنت تحفظ سورة جديدة أو تراجع وردك اليومي، يسجل هذا التطبيق صوتك ويحدد الكلمات على الشاشة أثناء التلاوة فوراً.",
    about2Part1: "يعالج صوتك بالكامل على جهازك. ",
    about2Highlight: "لا يتطلب اتصالاً بالإنترنت",
    about2Part2: "، مما يضمن خصوصيتك التامة ويتيح لك التدرب في أي مكان وزمان.",
    forAllah: "\"لوجه الله تعالى\"",
    featuresTitle: "ميزات قوية لحفظك",
    f1Title: "تتبع الكلمات في الوقت الفعلي",
    f1Desc: "شاهد الكلمات تضيء باللون الأخضر عندما تقرأ بشكل صحيح، واكتشف فوراً الكلمات التي تم تخطيها أو نسيانها والمحددة باللون الأحمر.",
    f2Title: "بدون إنترنت وخاص 100%",
    f2Desc: "صوتك لا يغادر هاتفك أبدًا. تتم جميع معالجة الصوت محليًا لضمان الخصوصية التامة وعدم استخدام بيانات الهاتف المحمول.",
    f3Title: "التمرير التلقائي الذكي",
    f3Desc: "يتم تمرير الشاشة تلقائيًا لمواكبة سرعة تلاوتك، مما يتيح لك تجربة قراءة بدون استخدام اليدين بالكامل.",
    f4Title: "تصحيح التجويد والتشكيل",
    f4Desc: "يبرز أخطاء المدود والغنة والتشكيل باللون الأصفر فوراً، مما يساعدك على إتقان أحكام التجويد بدقة.",
    f5Title: "البحث الصوتي الذكي",
    f5Desc: "اتلُ أي آية في الميكروفون، وسيقوم التطبيق بالبحث في القرآن الكريم بأكمله والانتقال إليها تلقائياً.",
    readyStart: "جاهز للبدء؟",
    experienceAi: "جربه محلياً على جهازك.",
    downloadNow: "حمل الآن",
    screenTitle: "واجهة بسيطة وجميلة",
    screenDesc: "صُممت لتقليل المشتتات أثناء تركيزك على كتاب الله.",
    screen1: "لقطة شاشة لوضع القراءة",
    screen2: "لقطة شاشة لفحص الأخطاء",
    screen3: "لقطة شاشة لقائمة الإعدادات",
    placeHere: "ضعها هنا",
    privacyTitle: "خصوصيتك، مضمونة",
    privacyDesc: "لا توجد مزامنة سحابية. لا حاجة للإنترنت. قم بمعالجة تلاوتك محلياً وتدرب براحة بال تامة.",
    availableNow: "متاح الآن",
    footerDesc: "حسّن تلاوتك وحفظك للقرآن العظيم.",
    policy: "سياسة الخصوصية",
    terms: "شروط الخدمة",
    contact: "تواصل مع الدعم",
    rights: "WayOfTheSalaf. جميع الحقوق محفوظة."
  }
};

export default function App() {
  const [lang, setLang] = useState<'en' | 'ar'>('ar');
  const t = content[lang];
  const isAr = lang === 'ar';

  return (
    <div dir={isAr ? 'rtl' : 'ltr'} className={`min-h-screen bg-neutral-50 text-neutral-900 selection:bg-emerald-200 ${isAr ? 'font-arabic' : 'font-sans'}`}>
      
      <main>
        {/* Hero Section */}
        <section className="pt-12 pb-16 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto flex flex-col lg:flex-row items-center gap-12 lg:gap-8">
          {/* Left Text */}
          <div className="flex-1 text-center lg:text-start">
            <div className="flex flex-col items-center lg:items-start mb-6">
              <h1 className="text-5xl md:text-6xl lg:text-7xl font-extrabold tracking-tight text-neutral-900 mb-5">
                {t.heroTitleEn} <span className={`block text-4xl md:text-5xl lg:text-6xl text-emerald-600 mt-2 ${isAr ? 'font-sans' : 'font-arabic'}`}>{t.heroTitleAr}</span>
              </h1>
              <button 
                onClick={() => setLang(isAr ? 'en' : 'ar')}
                className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-emerald-800 bg-emerald-100 hover:bg-emerald-200 transition-colors rounded-full"
              >
                <Globe className="w-4 h-4" />
                <span dir="ltr">{isAr ? 'English' : 'العربية'}</span>
              </button>
            </div>
            
            <p className="max-w-2xl mx-auto lg:mx-0 text-xl text-neutral-600 mb-10 leading-relaxed">
              {t.heroDesc}
            </p>

            <div className="flex flex-col sm:flex-row justify-center lg:justify-start items-center gap-4">
              <a 
                href="/recite/"
                className="flex items-center justify-center gap-3 bg-emerald-600 hover:bg-emerald-700 text-white px-8 py-4 rounded-2xl font-bold transition-all hover:scale-105 shadow-lg shadow-emerald-600/20 w-full sm:w-auto"
              >
                <Globe className="w-6 h-6" />
                <div className="text-start">
                  <div className="text-sm font-bold uppercase tracking-wider leading-none">{t.tryWeb}</div>
                </div>
              </a>
              <a 
                href="https://play.google.com/store/apps/details?id=com.recitequran.app"
                target="_blank" 
                rel="noopener noreferrer"
                className="flex items-center justify-center gap-3 bg-white border border-neutral-200 hover:bg-neutral-50 text-neutral-900 px-6 py-4 rounded-2xl font-semibold transition-all hover:scale-105 w-full sm:w-auto"
              >
                <svg viewBox="0 0 512 512" className="w-5 h-5 fill-current">
                  <path d="M325.3 234.3L104.6 13l280.8 161.2-60.1 60.1zM47 0C34 6.8 25.3 19.2 25.3 35.3v441.3c0 16.1 8.7 28.5 21.7 35.3l256.6-256L47 0zm425.2 225.6l-58.9-34.1-65.7 64.5 65.7 64.5 60.1-34.1c18-14.3 18-46.5-1.2-60.8zM104.6 499l280.8-161.2-60.1-60.1L104.6 499z" />
                </svg>
                <div className="text-start">
                  <div className="text-[10px] uppercase tracking-wider leading-none opacity-80">{t.getOn}</div>
                  <div className="text-sm leading-none mt-1">{t.googlePlay}</div>
                </div>
              </a>
            </div>
          </div>

          {/* Right Phone Mockup - Mistake Checker */}
          <div className="flex-1 flex justify-center lg:justify-end w-full">
            <div className="w-[280px] h-[580px] bg-neutral-900 rounded-[3rem] p-2 shadow-2xl relative">
              <div className="w-full h-full bg-neutral-100 rounded-[2.5rem] overflow-hidden relative border border-black max-w-full bg-[#fdfaf6]">
                <div className="absolute top-0 inset-x-0 h-6 flex justify-center z-20">
                  <div className="w-32 h-6 bg-neutral-900 rounded-b-xl"></div>
                </div>
                <img src="/recitequran.jpg" alt="Screenshot" className="w-full h-full object-cover block absolute inset-0" />
              </div>
            </div>
          </div>
        </section>

        {/* Introduction / About */}
        <section className="py-20 bg-white border-y border-neutral-100">
          <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center text-lg text-neutral-600 leading-relaxed space-y-6">
            <p>{t.about1}</p>
            <p>
              {t.about2Part1}<strong className="text-neutral-900 relative"><span className="relative z-10">{t.about2Highlight}</span><span className="absolute bottom-1 inset-x-0 h-2 bg-emerald-200 -z-10"></span></strong>{t.about2Part2}
            </p>
            <p className="text-emerald-700 font-medium italic mt-8">
              {t.forAllah}
            </p>
          </div>
        </section>

        {/* Features Section */}
        <section className="py-24 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold tracking-tight text-neutral-900">
              {t.featuresTitle}
            </h2>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 lg:gap-6">
            <div className="bg-white p-6 rounded-2xl shadow-sm border border-neutral-100 hover:shadow-md transition-shadow">
              <div className="w-10 h-10 bg-emerald-100 rounded-xl flex items-center justify-center mb-4 text-emerald-600">
                <CheckCircle2 className="w-5 h-5" />
              </div>
              <h3 className="text-lg font-bold mb-2">{t.f1Title}</h3>
              <p className="text-sm text-neutral-600 leading-relaxed">
                {t.f1Desc}
              </p>
            </div>

            <div className="bg-white p-6 rounded-2xl shadow-sm border border-neutral-100 hover:shadow-md transition-shadow">
              <div className="w-10 h-10 bg-emerald-100 rounded-xl flex items-center justify-center mb-4 text-emerald-600">
                <ShieldCheck className="w-5 h-5" />
              </div>
              <h3 className="text-lg font-bold mb-2">{t.f2Title}</h3>
              <p className="text-sm text-neutral-600 leading-relaxed">
                {t.f2Desc}
              </p>
            </div>

            <div className="bg-white p-6 rounded-2xl shadow-sm border border-neutral-100 hover:shadow-md transition-shadow">
              <div className="w-10 h-10 bg-emerald-100 rounded-xl flex items-center justify-center mb-4 text-emerald-600">
                <MoveDown className="w-5 h-5" />
              </div>
              <h3 className="text-lg font-bold mb-2">{t.f3Title}</h3>
              <p className="text-sm text-neutral-600 leading-relaxed">
                {t.f3Desc}
              </p>
            </div>

            <div className="bg-white p-6 rounded-2xl shadow-sm border border-neutral-100 hover:shadow-md transition-shadow">
              <div className="w-10 h-10 bg-emerald-100 rounded-xl flex items-center justify-center mb-4 text-emerald-600">
                <SlidersHorizontal className="w-5 h-5" />
              </div>
              <h3 className="text-lg font-bold mb-2">{t.f4Title}</h3>
              <p className="text-sm text-neutral-600 leading-relaxed">
                {t.f4Desc}
              </p>
            </div>

            <div className="bg-white p-6 rounded-2xl shadow-sm border border-neutral-100 hover:shadow-md transition-shadow">
              <div className="w-10 h-10 bg-emerald-100 rounded-xl flex items-center justify-center mb-4 text-emerald-600">
                <Type className="w-5 h-5" />
              </div>
              <h3 className="text-lg font-bold mb-2">{t.f5Title}</h3>
              <p className="text-sm text-neutral-600 leading-relaxed">
                {t.f5Desc}
              </p>
            </div>
            
            {/* Aesthetic Filler / CTA Card */}
            <div className="bg-emerald-600 p-6 rounded-2xl shadow-sm flex flex-col justify-center items-center text-center text-white">
              <Mic className="w-10 h-10 mb-3 opacity-80" />
              <h3 className="text-lg font-bold mb-2">{t.readyStart}</h3>
              <p className="text-sm text-emerald-100 mb-4">{t.experienceAi}</p>
              <a href="https://play.google.com/store/apps/details?id=com.recitequran.app" target="_blank" rel="noopener noreferrer" className="bg-white text-emerald-700 px-5 py-2 rounded-full text-sm font-bold hover:bg-emerald-50 transition-colors">
                {t.downloadNow}
              </a>
            </div>
          </div>
        </section>

      </main>

      {/* Footer */}
      <footer className="bg-white border-t border-neutral-200 py-12 px-4 sm:px-6 lg:px-8 text-center text-neutral-500">
        <div className="max-w-7xl mx-auto flex flex-col items-center">
          <div className="flex items-center justify-center gap-3 mb-4">
            <img src="/app_icon.png" alt="Logo" className="w-8 h-8 object-contain" />
            <span className="font-bold text-lg text-neutral-900">{t.navTitle}</span>
          </div>
          <p className="text-sm">{t.footerDesc}</p>
        </div>
      </footer>
    </div>
  );
}

