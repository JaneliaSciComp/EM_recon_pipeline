process GET_STACK_Z_VALUES_JSON {
    input:
    val baseDataUrl
    val stackOwner
    val project
    val stack
    val minZString
    val maxZString

    output:
    stdout emit: z_values_json_text

    script:
    def queryParameters = ''
    if (minZString.length() > 0) {
        if (maxZString.length() > 0) {
            queryParameters = "?minZ=${minZString}&maxZ=${maxZString}"
        } else {
            queryParameters = "?minZ=${minZString}"
        }
    } else if (maxZString.length() > 0) {
        queryParameters = "?maxZ=${maxZString}"
    }
    def url = "${baseDataUrl}/owner/${stackOwner}/project/${project}/stack/${stack}/zValues"
    """
    curl -s "${url}${queryParameters}"
    """
}