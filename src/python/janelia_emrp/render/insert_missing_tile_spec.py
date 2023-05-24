#!/usr/bin/env python

from janelia_emrp.render.web_service_request import RenderRequest


def main():
    render_request = RenderRequest(host='em-services-1.int.janelia.org:8080',
                                   owner='cellmap',
                                   project='jrc_mus_pancreas_4')
    stack = "v5_acquire"

    prior_resolved_tiles = render_request.get_resolved_tiles_for_z(stack, 699)
    tile_spec = prior_resolved_tiles["tileIdToSpecMap"]["23-04-22_101504_0-1-1.699.0"]

    resolved_tiles = render_request.get_resolved_tiles_for_z(stack, 700)
    left_tile_spec = resolved_tiles["tileIdToSpecMap"]["23-04-22_101658_0-1-0.700.0"]

    tile_id = "23-04-22_101658_0-1-1.700.0"
    tile_spec["tileId"] = tile_id
    tile_spec["layout"]["sectionId"] = left_tile_spec["layout"]["sectionId"]
    tile_spec["z"] = left_tile_spec["z"]

    image_url = left_tile_spec["mipmapLevels"]["0"]["imageUrl"]
    tile_spec["mipmapLevels"]["0"]["imageUrl"] = image_url.replace("dataSet=/0-1-0", "dataSet=/0-1-1")

    resolved_tiles["tileIdToSpecMap"][tile_id] = tile_spec

    render_request.set_stack_state_to_loading(stack)
    render_request.save_resolved_tiles(stack, resolved_tiles)
    render_request.set_stack_state_to_complete(stack)


if __name__ == '__main__':
    main()
