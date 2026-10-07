# Store / cosmetic assets (staged, not wired in)

`exodus/shaders/` (121 `.frag`/`.vert`, outfit, aura, map shaders) and `exodus/shader_images/` (20 textures) come from the Hellgrave Exodus client, the one that matches our server's `addShader`, wings and auras. Only 4 of the 95 outfit shaders are plain fragment shaders; the other 91 need OTCv8's custom vertex stage (`expand_vertex`, `u_Offset`, `u_Center`, `v_TexCoord2/3`).

The wing, aura, mount and outfit **sprites** live inside `Tibia.spr`/`Tibia.dat`, not as loose files, so they travel with your 10.98 spr/dat pair.

Other clients hold more (counted from file lists): Black Talon has the biggest set of shaders (about 640 files) and 128 sprite/dat files; MagicHeard has 187 spr/dat/cwm files and 24 wing/aura images. Not copied yet: unclear licence and size.

`blacktalon/shaders/` (635 `.frag`, 5 `.vert`, textures): Black Talon's shader set, copied with the owner's permission. Black Talon is a different client lineage, so check each shader against the uniforms Astra provides before registering it.
