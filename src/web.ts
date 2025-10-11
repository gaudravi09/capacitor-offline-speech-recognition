import { WebPlugin } from '@capacitor/core';

import type { OfflineSpeechRecognitionPlugin } from './definitions';

export class OfflineSpeechRecognitionWeb extends WebPlugin implements OfflineSpeechRecognitionPlugin {
  async echo(options: { value: string }): Promise<{ value: string }> {
    console.log('ECHO', options);
    return options;
  }
}
