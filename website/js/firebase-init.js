// party_app/lib/firebase_options.dart의 web 설정과 동일한 프로젝트를 그대로
// 가리킨다 — Firestore/Auth 데이터는 앱과 완전히 공유된다(별도 백엔드 없음).
import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.7.1/firebase-app.js';
import { getFirestore } from 'https://www.gstatic.com/firebasejs/10.7.1/firebase-firestore.js';
import { getAuth } from 'https://www.gstatic.com/firebasejs/10.7.1/firebase-auth.js';

const firebaseConfig = {
  apiKey: 'AIzaSyBW-MoTttcXT7ge8bo3wNpeXoHzjSrlM5Y',
  authDomain: 'partychu-30c24.firebaseapp.com',
  projectId: 'partychu-30c24',
  storageBucket: 'partychu-30c24.firebasestorage.app',
  messagingSenderId: '494588817221',
  appId: '1:494588817221:web:e09942e141a6f1e1df182c',
  measurementId: 'G-3J6CZ02T7Y',
};

export const app = initializeApp(firebaseConfig);
export const db = getFirestore(app);
export const auth = getAuth(app);
