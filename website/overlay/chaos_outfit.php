<?php
/**
 * Outfit images of Cinders of Chaos (website/README.md "Sprite images"): ZnoteX's show_outfits imageServer.
 *   /chaos_outfit.php?id=<look>&addons=0..3&head=&body=&legs=&feet=[&mount=<look>]
 * Draws the look from the sheets that website/tools/gen_sprite_images.py wrote to chaos-sprites/ (only our art;
 * anything else is a neutral placeholder). Loads nothing of ZnoteX: no session, no database.
 */
require __DIR__ . '/plugins/chaos/sprite_lib.php';
chaos_outfit_serve($_GET);
