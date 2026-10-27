#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    clientservices::fuzz_checks::check_request(data);
});
