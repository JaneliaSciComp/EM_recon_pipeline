#!/usr/bin/env python

from janelia_emrp.render.web_service_request import RenderRequest


def main():
    render_request = RenderRequest(host='em-services-1.int.janelia.org:8080',
                                   owner='fibsem',
                                   project='jrc_maph_mefs_1')
    stack = "v3_acquire_mask"

    z_layers_to_patch = render_request.get_z_values(stack)

    render_request.set_stack_state_to_loading(stack)

    for z_str in z_layers_to_patch:
        z = int(z_str)
        if z >= 6000:
            resolved_tiles = render_request.get_resolved_tiles_for_z(stack, z)
            for tile_id in resolved_tiles["tileIdToSpecMap"]:
                tile_spec = resolved_tiles["tileIdToSpecMap"][tile_id]
                mipmap_zero = tile_spec["mipmapLevels"]["0"]

                #   change mask://outside-box?minX=100&minY=0&maxX=6250&maxY=1875&width=6250&height=1875
                #   to     mask://outside-box?minX=2000&minY=875&maxX=3000&maxY=1875&width=6250&height=1875
                mipmap_zero["maskUrl"] = "mask://outside-box?minX=2000&minY=875&maxX=3000&maxY=1875&width=6250&height=1875"

                render_request.save_resolved_tiles(stack, resolved_tiles)

    render_request.set_stack_state_to_complete(stack)


if __name__ == '__main__':
    main()
