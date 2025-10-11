package dev.ravi.offlinespeech;

import com.getcapacitor.Logger;

public class OfflineSpeechRecognition {

    public String echo(String value) {
        Logger.info("Echo", value);
        return value;
    }
}
