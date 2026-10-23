// Regression driver for the libFuzzer harnesses of server/tools/fuzz/ (server/README.md "Engine hardening"): links
// with one fuzz_*.cpp instead of -fsanitize=fuzzer and runs LLVMFuzzerTestOneInput once per file, so CI checks the
// seed corpus and every saved crash input quickly with g++ and the sanitizers, without libFuzzer.
//   usage: HARNESS FILE_OR_DIR...   (exit status 0: every input ran; a sanitizer report or a crash ends it non-zero)
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <string>
#include <vector>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size);
extern "C" int LLVMFuzzerInitialize(int* argc, char*** argv) __attribute__((weak));

static int runFile(const std::filesystem::path& path)
{
	std::ifstream in(path, std::ios::binary);
	if (!in) {
		std::cerr << "cannot read " << path << std::endl;
		return 1;
	}
	std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
	// a copy of exactly the input's size on the heap, so AddressSanitizer sees a read past its end
	std::unique_ptr<uint8_t[]> copy(new uint8_t[bytes.size() ? bytes.size() : 1]);
	std::copy(bytes.begin(), bytes.end(), copy.get());
	LLVMFuzzerTestOneInput(copy.get(), bytes.size());
	return 0;
}

int main(int argc, char** argv)
{
	if (LLVMFuzzerInitialize) {
		LLVMFuzzerInitialize(&argc, &argv);
	}
	size_t ran = 0;
	int bad = 0;
	// the empty input first: every harness must take it
	LLVMFuzzerTestOneInput(reinterpret_cast<const uint8_t*>(""), 0);
	for (int i = 1; i < argc; ++i) {
		std::filesystem::path p(argv[i]);
		std::vector<std::filesystem::path> files;
		if (std::filesystem::is_directory(p)) {
			for (const auto& e : std::filesystem::recursive_directory_iterator(p)) {
				if (e.is_regular_file()) {
					files.push_back(e.path());
				}
			}
			std::sort(files.begin(), files.end());
		} else {
			files.push_back(p);
		}
		for (const auto& f : files) {
			bad |= runFile(f);
			++ran;
		}
	}
	std::printf("%s: %zu inputs ran\n", argv[0], ran);  // printf: a harness may silence std::cout
	return bad;
}
