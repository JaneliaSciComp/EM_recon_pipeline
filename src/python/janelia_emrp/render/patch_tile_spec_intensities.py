#!/usr/bin/env python

from janelia_emrp.render.web_service_request import RenderRequest


def patch_filter_data_string(data_string: str,
                             additive_offset: float):
    filter_parameters = data_string.split(',')

    number_of_region_rows = int(filter_parameters[0])
    number_of_region_columns = int(filter_parameters[1])
    coefficients_per_region = int(filter_parameters[2])
    if coefficients_per_region != 2:
        raise AttributeError(f"filter data string should only specify 2 coefficients per region: {data_string}")

    number_of_values = number_of_region_rows * number_of_region_columns * coefficients_per_region

    # multiplicative factor, additive factor, multiplicative factor, additive factor, ...
    for index in range(3+1, 3+number_of_values, 2):
        updated_value = float(filter_parameters[index]) + additive_offset
        filter_parameters[index] = str(updated_value)

    return ','.join(filter_parameters)


def main():
    render_request = RenderRequest(host='em-services-1.int.janelia.org:8080',
                                   owner='cellmap',
                                   project='jrc_zf_cardiac_2')
    stack = "v4_acquire_align_ic_try4"
    additive_offset = -4.0 / 256.0  # need to divide by intensity range for 8-bit!
    z_layers_to_patch = [12983, 12984, 12985, 12986, 12987, 12988, 12989,
                         12990, 12991, 12992, 12993, 12994, 12995, 12996]

    render_request.set_stack_state_to_loading(stack)
    
    for z in z_layers_to_patch:
        resolved_tiles = render_request.get_resolved_tiles_for_z(stack, z)
        for tile_id in resolved_tiles["tileIdToSpecMap"]:
            tile_spec = resolved_tiles["tileIdToSpecMap"][tile_id]
            patched_data_string = \
                patch_filter_data_string(data_string=tile_spec["filterSpec"]["parameters"]["dataString"],
                                         additive_offset=additive_offset)
            tile_spec["filterSpec"]["parameters"]["dataString"] = patched_data_string
        render_request.save_resolved_tiles(stack, resolved_tiles)

    render_request.set_stack_state_to_complete(stack)


if __name__ == '__main__':
    main()
