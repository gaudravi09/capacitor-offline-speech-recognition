export interface OfflineSpeechRecognitionPlugin {
  echo(options: { value: string }): Promise<{ value: string }>;
}
