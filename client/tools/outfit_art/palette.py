"""The materials of the Season of Ash: charred iron, embers, ash, bone, cracked obsidian, old leather. Tinted
materials (region set) are neutral grey: the client multiplies them by the player's colours."""
from rig import Mat, grey, ramp

DARK = (12, 9, 10)          # the outline of almost everything


def base_mats():
    return {
        "skin": Mat(ramp([(58, 28, 24), (118, 68, 50), (176, 116, 84), (222, 164, 122), (244, 202, 162)], 6), (34, 14, 10)),
        "ashskin": Mat(ramp([(40, 28, 28), (84, 64, 60), (128, 104, 94), (168, 144, 128), (198, 178, 160)], 6), (22, 12, 10)),
        "horn": Mat(ramp([(30, 24, 22), (70, 60, 52), (126, 114, 96), (186, 174, 150), (226, 218, 196)], 6), (14, 10, 8)),
        "eye": Mat(ramp([(14, 8, 8), (40, 26, 22)], 2), DARK),
        "iron": Mat(ramp([(16, 14, 19), (36, 33, 41), (60, 56, 64), (92, 87, 93), (132, 125, 126), (184, 172, 160)], 7),
                    DARK, kind="metal", spec=0.30),
        "steel": Mat(ramp([(34, 36, 44), (84, 88, 98), (142, 146, 150), (204, 206, 202), (242, 238, 226)], 6), DARK,
                     kind="metal", spec=0.35),
        "ember": Mat(ramp([(132, 30, 10), (216, 78, 18), (255, 148, 42), (255, 220, 128)], 4), (70, 14, 6), kind="glow"),
        "bone": Mat(ramp([(50, 44, 38), (96, 88, 76), (140, 132, 114), (182, 174, 152), (216, 208, 186)], 6), (26, 20, 16)),
        "obsidian": Mat(ramp([(8, 6, 12), (22, 17, 30), (42, 34, 56), (72, 62, 92), (118, 108, 142)], 6), (4, 3, 8),
                        kind="metal", spec=0.55),
        "leather": Mat(ramp([(26, 16, 12), (54, 34, 23), (88, 58, 37), (126, 90, 57), (160, 122, 80)], 6), (16, 9, 6)),
        "wood": Mat(ramp([(40, 26, 18), (78, 52, 33), (118, 84, 52), (156, 120, 78), (186, 150, 100)], 6), (18, 11, 7)),
        "ash": Mat(ramp([(46, 44, 46), (86, 84, 84), (132, 128, 124), (176, 170, 162)], 5), (20, 19, 20), grain=0.6),
        # tinted (the player's colours)
        "hair": Mat(grey(5, 60, 236), (16, 14, 14), "head", grain=0.5),
        "plume": Mat(grey(5, 64, 246), (16, 14, 14), "head", grain=0.7),
        "cloth": Mat(grey(6, 56, 246), (16, 15, 16), "body"),
        "fur": Mat(grey(5, 62, 240), (18, 16, 16), "body", grain=0.9),
        "pants": Mat(grey(6, 50, 236), (16, 15, 16), "legs"),
        "kilt": Mat(grey(5, 56, 236), (16, 15, 16), "legs", grain=0.4),
        "boot": Mat(grey(5, 44, 220), (14, 13, 14), "feet"),
        "bootmetal": Mat(grey(6, 40, 248), (14, 13, 14), "feet", kind="metal", spec=0.3),
    }
