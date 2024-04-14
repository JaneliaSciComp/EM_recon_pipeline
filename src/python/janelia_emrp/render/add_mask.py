#!/usr/bin/env python

from janelia_emrp.render.web_service_request import RenderRequest


def add_mask(tile_spec):
    mipmap_zero = tile_spec["mipmapLevels"]["0"]
    mipmap_zero["maskUrl"] = f"mask://outside-box?minX=0&minY=10&maxX=2000&maxY=1748&width=2000&height=1748"
    mipmap_zero["maskLoaderType"] = "DYNAMIC_MASK"


def main():
    render_request = RenderRequest(host='em-services-1.int.janelia.org:8080',
                                   owner='hess_wafer_53d',
                                   project='slab_120_to_129')
    stack = "s127_m232_align_mi_ic_test1_with_mask10"

    z_layers_to_patch = render_request.get_z_values(stack)

    render_request.set_stack_state_to_loading(stack)
    
    for z in z_layers_to_patch:
        resolved_tiles = render_request.get_resolved_tiles_for_z(stack, z)
        for tile_id in resolved_tiles["tileIdToSpecMap"]:
            tile_spec = resolved_tiles["tileIdToSpecMap"][tile_id]
            add_mask(tile_spec)
        render_request.save_resolved_tiles(stack, resolved_tiles)

    render_request.set_stack_state_to_complete(stack)


if __name__ == '__main__':
    main()
