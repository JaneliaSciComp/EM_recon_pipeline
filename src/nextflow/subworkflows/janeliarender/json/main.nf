#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

workflow SPLIT_JSON_ARRAY_TEXT_INTO_FML_CHANNELS {
    take:
    z_values_json_text

    emit:
    first_ch
    middle_ch
    last_ch

    main:
    def parser = new groovy.json.JsonSlurper()
    def split_channels = z_values_json_text.flatMap {

        def list = parser.parseText(it)

        def first = []
        def middle = []
        def last = []

        if (list.size() > 2) {

            first = [list.get(0)]
            middle = list.subList(1, list.size() - 1)
            last = [list.get(list.size() - 1)]

        } else if (list.size() == 2) {

            first = [list.get(0)]
            last = [list.get(1)]

        } else if (list.size() == 1) {

            last = [list.get(0)]

        }

        [first, middle, last]
    }
    first_ch = split_channels.first().flatMap()
    middle_ch = split_channels.take(2).last().flatMap()
    last_ch = split_channels.last().flatMap()
}