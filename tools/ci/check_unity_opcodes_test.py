#!/usr/bin/env python3
"""check_unity_opcodes.py on a small made-up tree and on the real repo (clean). python3 -I tools/ci/check_unity_opcodes_test.py"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_unity_opcodes as C  # noqa: E402

CONSTANTS = '''
ChaosOpcodes = {
	bank = 60, -- a comment 99
	guild = 252,
	hud = 224
}
ChaosOpcodes.survey = 122
ChaosOpcodes.retired = 111
-- ChaosOpcodes.commented = 150
'''

MODULE = '''
local OPCODE = 217
local CODE = 250
ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
ProtocolGame.unregisterExtendedOpcode(OPCODE)
ProtocolGame.registerExtendedOpcode(CODE, safe('opcode', f))
ProtocolGame.registerExtendedOpcode(unknownName, f)
ProtocolGame.registerExtendedOpcode(77, f)
'''

CS = '''
namespace X {
  public static class HudOp {
    public const byte Shield = 224, Other = 225;
  }
  public sealed class A {
    public const byte Opcode = 60;
    public A(ExtOpcodes e) { e.On(Opcode, m => { }); }
  }
  public sealed class B {
    public const byte Opcode = 252, TravelOpcode = 121;
    public B(ExtOpcodes e) { ext = e; ext.On(Opcode, OnMessage); ext.Send(TravelOpcode, "go"); }
  }
  public sealed class C : CollectModel {
    public const byte OpcodeId = 250;
    public C(ExtOpcodes e) : base(e, OpcodeId) { }
  }
  public sealed class D { public D(ExtOpcodes e) { e.On(122, m => { }); e.OnText((byte)217, t => { }); } }
  public sealed class NotHandled { public const byte Opcode = 99; void F() { var x = Opcode; } }
}
'''


def tree(files):
    root = tempfile.mkdtemp(prefix='unity_opcodes_')
    for rel, text in files.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(text)
    return root


def main():
    root = tree({
        C.CONSTANTS: CONSTANTS,
        'client/overlay/modules/game_x/x.lua': MODULE,
        'client/overlay/modules/game_x/x_test.lua': 'ProtocolGame.registerExtendedOpcode(5, f)',
        'unity/Client/Assets/Chaos/Core/X.cs': CS,
    })
    server = C.server_opcodes(root)
    assert sorted(server) == [60, 111, 122, 224, 252], sorted(server)
    assert server[60] == ['ChaosOpcodes.bank'], server[60]
    client = C.client_opcodes(root)
    assert sorted(client) == [77, 217, 250], sorted(client)
    handled = C.unity_handled(root)
    # On(Opcode) with the constant of its class, a multi-declarator const, a base(e, N) call, literals, a cast, HudOp members, a Send by name
    assert {60, 252, 121, 250, 122, 217, 224, 225} <= handled, sorted(handled)
    assert 99 not in handled and 111 not in handled and 77 not in handled, sorted(handled)

    # the real check on this tree: 111 and 77 have no handler
    bad = C.problems(server, client, handled, {})
    assert any('opcode 111 ' in b for b in bad) and any('opcode 77 ' in b for b in bad), bad
    assert not any('opcode 60 ' in b for b in bad), bad
    # an allowlist entry covers them; one for a handled opcode is refused (the list can only shrink); one for a number nobody names too
    assert C.problems(server, client, handled, {111: 'retired for good', 77: 'not ported yet: a test'}) == []
    bad = C.problems(server, client, handled, {111: 'retired for good', 77: 'not ported yet: a test', 60: 'was missing once'})
    assert len(bad) == 1 and 'handled in Unity now' in bad[0], bad
    bad = C.problems(server, client, handled, {111: 'retired for good', 77: 'not ported yet: a test', 5: 'gone from the project'})
    assert len(bad) == 1 and 'not a client-facing opcode' in bad[0], bad
    bad = C.problems(server, client, handled, {111: 'x', 77: 'not ported yet: a test'})
    assert any('needs a real reason' in b for b in bad), bad

    # the allowlist file format
    allow_root = tree({C.ALLOW: '# comment\n\n12 | not ported yet: a module\n13|retired\n'})
    assert C.load_allow(allow_root) == {12: 'not ported yet: a module', 13: 'retired'}
    for text in ('12\n', 'x | reason\n', '12 |\n', '12 | a reason\n12 | again\n'):
        try:
            C.load_allow(tree({C.ALLOW: text}))
        except ValueError:
            continue
        raise AssertionError('accepted: %r' % text)

    # the real repository is clean
    assert C.main([]) == 0
    real = C.problems(C.server_opcodes(), C.client_opcodes(), C.unity_handled(), C.load_allow())
    assert real == [], real
    # the opcodes the Unity track of this phase ported are handled
    for op in (120, 122, 163, 171, 172, 194, 203, 217, 220, 244):
        assert op in C.unity_handled(), op
    print('check_unity_opcodes_test: ok')


if __name__ == '__main__':
    main()
