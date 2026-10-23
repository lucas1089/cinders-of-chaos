// Fuzz harness: the engine's incoming network message (src/networkmessage.h, NetworkMessage::getString and
// getPosition of networkmessage.cpp), the packet framing of Connection::parseHeader / parsePacket (length header,
// adler32 checksum), Protocol's XTEA_decrypt, and the read sequences of the two first messages
// (ProtocolLogin::onRecvFirstMessage, ProtocolGame::onRecvFirstMessage). The input is the byte stream of one
// connection. Needs the patched engine source (server/tools/build_sanitized.sh makes it): build_fuzz.sh --src
// takes the four engine functions out of it into netmsg_engine.inc and builds this file with the real headers.
//
// The framing and the read sequences are a copy of the engine's, kept short: the RSA blocks are taken as already
// decrypted (the fuzzer cannot make valid RSA), and the reads stop where the engine goes to the database or the game.
// Checks: AddressSanitizer / UBSan on every read; a read past the bytes the connection received (the engine allows
// 8 bytes there for a plain first message) returns zeros (src-patch 0063), never bytes of an earlier packet or memory
// never written (src-patch 0032 took the buffer's zeroing out). Without 0063 the first input of
// corpus/netmsg/regress-* trips it.
#include "otpch.h"

#include "networkmessage.h"
#include "position.h"
#include "xtea.h"

#include <cstring>
#include <memory>

uint32_t adlerChecksum(const uint8_t* data, size_t length);
#include "netmsg_engine.inc" // getString, getPosition, adlerChecksum, XTEA_decrypt: copied from the engine source

namespace {

// how far the connection filled the buffer for the packet being parsed (buffer index, exclusive)
size_t receivedEnd = 0;

class Msg : public NetworkMessage
{
	public:
		// the engine's canRead allows reads up to info.length + 8, which for a first (plain) message is 8 bytes past
		// its end: what a read there returns must be the zeros of src-patch 0063, never an earlier packet's bytes
		void checkReceived() const {
			for (size_t i = receivedEnd; i < info.position; ++i) {
				if (buffer[i] != 0) {
					__builtin_trap();
				}
			}
		}
};

struct Stream {
	const uint8_t* data;
	size_t size;
	size_t at = 0;
	bool take(uint8_t* out, size_t n) {
		if (size - at < n) {
			return false;
		}
		std::memcpy(out, data + at, n);
		at += n;
		return true;
	}
};

// Connection::parseHeader: false when the engine closes the connection
bool readPacket(Stream& s, Msg& msg)
{
	if (!s.take(msg.getBuffer(), NetworkMessage::HEADER_LENGTH)) {
		return false;
	}
	const uint16_t size = msg.getLengthHeader();
	if (size == 0 || size >= NETWORKMESSAGE_MAXSIZE - 16) {
		return false;
	}
	msg.setLength(size + NetworkMessage::HEADER_LENGTH);
	std::memset(msg.getBuffer() + NetworkMessage::HEADER_LENGTH + size, 0, NetworkMessage::INITIAL_BUFFER_POSITION);
	if (!s.take(msg.getBodyBuffer(), size)) {
		return false;
	}
	receivedEnd = size + NetworkMessage::HEADER_LENGTH;

	// Connection::parsePacket
	uint32_t checksum;
	int32_t len = msg.getLength() - msg.getBufferPosition() - NetworkMessage::CHECKSUM_LENGTH;
	if (len > 0) {
		checksum = adlerChecksum(msg.getBuffer() + msg.getBufferPosition() + NetworkMessage::CHECKSUM_LENGTH, len);
	} else {
		checksum = 0;
	}
	uint32_t recvChecksum = msg.get<uint32_t>();
	if (recvChecksum != checksum) {
		msg.skipBytes(-NetworkMessage::CHECKSUM_LENGTH);
	}
	return true;
}

// Protocol::RSA_decrypt without the RSA: the 128 bytes are taken as the plain block
bool plainRsa(Msg& msg)
{
	if ((msg.getLength() - msg.getBufferPosition()) < 128) {
		return false;
	}
	return msg.getByte() == 0;
}

void loginFirst(Msg& msg, xtea::round_keys& keys)
{
	msg.skipBytes(1); // protocol id (ServicePort::make_protocol)
	msg.skipBytes(2);
	uint16_t version = msg.get<uint16_t>();
	if (version >= 971) {
		msg.get<uint32_t>();
		msg.skipBytes(13);
	} else {
		msg.skipBytes(12);
	}
	if (version <= 760 || !plainRsa(msg)) {
		return;
	}
	xtea::key key;
	key[0] = msg.get<uint32_t>();
	key[1] = msg.get<uint32_t>();
	key[2] = msg.get<uint32_t>();
	key[3] = msg.get<uint32_t>();
	keys = xtea::expand_key(key);
	std::string accountName = msg.getString();
	std::string password = msg.getString();
	msg.checkReceived();
	if (accountName.empty() || password.empty()) {
		return;
	}
	uint16_t otcV8StringLength = msg.get<uint16_t>();
	if (otcV8StringLength == 5 && msg.getString(5) == "OTCv8") {
		msg.get<uint16_t>();
	}
	msg.checkReceived();
	msg.skipBytes((msg.getLength() - 128) - msg.getBufferPosition());
	if (!plainRsa(msg)) {
		return;
	}
	std::string authToken = msg.getString();
	msg.checkReceived();
}

void gameFirst(Msg& msg, xtea::round_keys& keys)
{
	msg.skipBytes(1); // protocol id (the game protocol exists already: Connection::parsePacket skips it)
	msg.get<uint16_t>();
	msg.get<uint16_t>();
	msg.get<uint32_t>();
	msg.skipBytes(3);
	if (!plainRsa(msg)) {
		return;
	}
	xtea::key key;
	key[0] = msg.get<uint32_t>();
	key[1] = msg.get<uint32_t>();
	key[2] = msg.get<uint32_t>();
	key[3] = msg.get<uint32_t>();
	keys = xtea::expand_key(key);
	msg.skipBytes(1);
	std::string sessionKey = msg.getString();
	std::string characterName = msg.getString();
	msg.get<uint32_t>();
	msg.getByte();
	msg.checkReceived();
	uint16_t otcV8StringLength = msg.get<uint16_t>();
	if (otcV8StringLength == 5 && msg.getString(5) == "OTCv8") {
		msg.get<uint16_t>();
		const std::string tierMarker = msg.getString();
		if (tierMarker == "OTCv8TierByte" && msg.getString() == "A") {
			msg.get<uint32_t>();
			if (msg.getString() == "C") {
				msg.getByte();
			}
		}
	}
	msg.checkReceived();
}

// XTEA_decrypt without the cipher: the fuzzer's bytes are the plain body, so the reads below see what it wrote
bool plainDecrypt(Msg& msg)
{
	if (((msg.getLength() - 6) & 7) != 0) {
		return false;
	}
	uint16_t innerLength = msg.get<uint16_t>();
	if (innerLength + 8 > msg.getLength()) {
		return false;
	}
	msg.setLength(innerLength);
	return true;
}

// a game packet after XTEA: the body's first byte drives a run of the reads ProtocolGame::parsePacket makes
void gamePacket(Msg& msg)
{
	for (int i = 0; i < 64; ++i) {
		switch (msg.getByte() % 7) {
			case 0: msg.getString(); break;
			case 1: msg.getPosition(); break;
			case 2: msg.get<uint16_t>(); break;
			case 3: msg.get<uint32_t>(); break;
			case 4: msg.get<uint64_t>(); break;
			case 5: msg.getString(msg.getByte()); break;
			default: msg.getByte(); break;
		}
		if (msg.isOverrun()) {
			break;
		}
	}
}

} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
	if (size < 1) {
		return 0;
	}
	// a Connection (and its NetworkMessage) lives on the heap; byte 0: login or game port, and whether the later
	// packets are XTEA decrypted with the key of the first one (as in the engine) or taken as already decrypted
	std::unique_ptr<Msg> msg(new Msg());
	std::memset(msg->getBuffer(), 0xA5, NETWORKMESSAGE_MAXSIZE); // "an earlier packet": not zero
	const bool login = (data[0] & 1) != 0;
	const bool plainLater = (data[0] & 2) != 0;
	Stream s{data + 1, size - 1};
	xtea::round_keys keys{};
	for (int packet = 0; packet < 16; ++packet) {
		msg->reset();
		if (!readPacket(s, *msg)) {
			break;
		}
		if (packet == 0) {
			if (login) {
				loginFirst(*msg, keys);
			} else {
				gameFirst(*msg, keys);
			}
			continue;
		}
		if (!(plainLater ? plainDecrypt(*msg) : XTEA_decrypt(*msg, keys))) {
			continue;
		}
		receivedEnd = msg->getLength() + NetworkMessage::INITIAL_BUFFER_POSITION; // the inner length
		gamePacket(*msg);
		msg->checkReceived();
	}
	return 0;
}
