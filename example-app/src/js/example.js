import { OfflineSpeechRecognition } from 'capacitor-offline-speech-recognition';

window.testEcho = () => {
    const inputValue = document.getElementById("echoInput").value;
    OfflineSpeechRecognition.echo({ value: inputValue })
}
