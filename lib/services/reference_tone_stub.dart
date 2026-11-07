/// Non-web stub: reference tones need a browser.
bool get referenceToneSupported => false;

Future<void> playTone(double freq, {double seconds = 1.2}) {
  throw UnsupportedError('Reference tones need a browser for now.');
}

Future<void> playStrum(List<double> freqs) {
  throw UnsupportedError('Audio preview needs a browser for now.');
}

Future<void> playArpeggio(List<double> freqs) {
  throw UnsupportedError('Audio preview needs a browser for now.');
}
