package app.capgo.plugin.document_scanner;

import com.getcapacitor.Logger;

public class DocumentScanner {

    public String echo(String value) {
        Logger.info("Echo", value);
        return value;
    }
}
