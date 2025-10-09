import { DocumentScanner } from '@capgo/capacitor-document-scanner';

window.testEcho = () => {
    const inputValue = document.getElementById("echoInput").value;
    DocumentScanner.echo({ value: inputValue })
}
