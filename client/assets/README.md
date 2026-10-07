# Store / cosmetic assets (staged, not wired in)

`base_shaders/shaders/` (121 `.frag`/`.vert`: outfit, aura and map shaders) and `base_shaders/shader_images/` (20 textures) match the server's `addShader`, wings and auras. Only 4 of the 95 outfit shaders are plain fragment shaders; the other 91 need the engine's custom vertex stage (`expand_vertex`, `u_Offset`, `u_Center`, `v_TexCoord2/3`).

`donor_shaders/shaders/` (635 `.frag`, 5 `.vert`, textures) is a second, larger shader set from a different client lineage: check each shader against the uniforms the base client provides before registering it.

The wing, aura, mount and outfit **sprites** live inside `Tibia.spr`/`Tibia.dat`, not as loose files, so they travel with your 10.98 spr/dat pair.
