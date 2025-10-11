import { registerPlugin } from '@capacitor/core';
import type { OfflineSpeechRecognitionPlugin } from './definitions';

const OfflineSpeechRecognition = registerPlugin<OfflineSpeechRecognitionPlugin>('OfflineSpeechRecognition');

export * from './definitions';
export { OfflineSpeechRecognition };
