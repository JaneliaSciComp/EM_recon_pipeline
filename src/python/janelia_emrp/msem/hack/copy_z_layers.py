#!/usr/bin/env python

from janelia_emrp.render.web_service_request import RenderRequest


def main():
    render_request = RenderRequest(host='em-services-1.int.janelia.org:8080',
                                   owner='hess_wafer_53d',
                                   project='slab_070_to_079')

    target_stack = "s070_m104_corrected_align_ic3d_z35_to_z37"

    stack_version = render_request.get_stack_metadata("s070_m104_corrected_align_ic3d_z34")["currentVersion"]
    stack_version["versionNotes"] = "derived from s070_m104_corrected_align_ic3d_z34"

    render_request.create_stack(stack=target_stack,
                                stack_version=stack_version)

    for z in range(35, 38):
        first_z = z - 1
        stack = f"s070_m104_corrected_align_ic3d_z{first_z}"
        resolved_tiles = render_request.get_resolved_tiles_for_z(stack, z)
        render_request.save_resolved_tiles(target_stack, resolved_tiles)

    render_request.set_stack_state_to_complete(target_stack)


if __name__ == '__main__':
    main()
