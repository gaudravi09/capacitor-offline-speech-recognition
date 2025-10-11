import { registerPlugin } from '@capacitor/core';

import type { OfflineSpeechRecognitionPlugin } from './definitions';

const OfflineSpeechRecognition = registerPlugin<OfflineSpeechRecognitionPlugin>('OfflineSpeechRecognition', {
  web: () => import('./web').then((m) => new m.OfflineSpeechRecognitionWeb()),
});

export * from './definitions';
export { OfflineSpeechRecognition };
