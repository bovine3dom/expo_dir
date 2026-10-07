#!/bin/julia

using Oxygen, JSON
using Humanize: datasize

PORT = get(ENV, "JULIA_API_PORT", 1989)

DIRECTORY = "/home/olie/projects/H3-MON/www/data/"

TARGET_ROOT = "expo/?data="

SUPPORTED_FORMATS = ["csv", "arrow", "parquet", "geojson"]

css = join(readlines(joinpath(@__DIR__, "simple.css")), "\n")

function extension_of(file)
    extension = splitext(file)[2]
    isempty(extension) ? "" : lowercase(extension[2:end])
end

function relative_metadata_key(root, file)
    relpath(joinpath(root, splitext(file)[1]), DIRECTORY)
end

function relative_data_key(root, file, extension)
    path = extension == "csv" ? joinpath(root, splitext(file)[1]) : joinpath(root, file)
    relpath(path, DIRECTORY)
end

function html_escape(value)
    return value # own use who cares
    # text = string(value)
    # text = replace(text, "&" => "&amp;")
    # text = replace(text, "<" => "&lt;")
    # text = replace(text, ">" => "&gt;")
    # text = replace(text, "\"" => "&quot;")
    # replace(text, "'" => "&#39;")
end

function get_trouvailles()
    trouvailles = Dict()
    metadata_by_key = Dict()
    metadata_key_by_entry = Dict()

    for (root, dirs, files) in walkdir(DIRECTORY)
        relative_root = relpath(root, DIRECTORY)
        depth = relative_root == "." ? 0 : length(splitpath(relative_root))
        depth >= 1 && empty!(dirs)

        for file in files
            extension = extension_of(file)
            if extension == "json"
                metadata_by_key[relative_metadata_key(root, file)] = JSON.parsefile(joinpath(root, file))
                continue
            end

            extension in SUPPORTED_FORMATS || continue

            key = relative_data_key(root, file, extension)
            trouvailles[key] = get(trouvailles, key, Dict())
            trouvailles[key][extension] = joinpath(root, file)
            metadata_key_by_entry[key] = relative_metadata_key(root, file)
        end
    end

    for (k,v) in trouvailles
        metadata_key = get(metadata_key_by_entry, k, k)
        if haskey(metadata_by_key, metadata_key)
            v["metadata"] = metadata_by_key[metadata_key]
        end

        for extension in SUPPORTED_FORMATS
            if haskey(v, extension)
                filepath = v[extension]
                v["filesize"] = datasize(filesize(filepath))
                v["modified"] = mtime(filepath)
                break
            end
        end
    end

    # Delete entries without any supported data format
    filter!(trouvailles) do (k, v)
        metadata = get(v, "metadata", Dict())
        get(metadata, "hidden", false) != true && any(extension -> haskey(v, extension), SUPPORTED_FORMATS)
    end

    keys_sorted = sort(collect(keys(trouvailles)), by=k -> get(trouvailles[k], "modified", 0), rev=true)
    return trouvailles, keys_sorted
end

get("/") do
    trouvailles, keys_sorted = get_trouvailles()
    html("<style>$css</style>
        <main>
        <h1>Map data experiments</h1>
        $(join(
                Iterators.map(
                    x -> begin
                        metadata = get(trouvailles[x], "metadata", Dict())
                        metadata_details = String[]
                        if haskey(metadata, "t")
                            desc = string(metadata["t"])
                            isempty(desc) || push!(metadata_details, html_escape(desc))
                        end
                        if haskey(metadata, "c")
                            attribution = string(metadata["c"])
                            isempty(attribution) || push!(metadata_details, "source: $(html_escape(attribution))")
                        end
                        bigness = get(trouvailles[x], "filesize", "")
                        link = html_escape(x)
                        size_html = isempty(bigness) ? "" : " ($(html_escape(bigness)))"
                        metadata_html = isempty(metadata_details) ? "" : "<dd><small>$(join(metadata_details, "<br>"))</small></dd>"
                        return "<dl><dt>$link$size_html</dt>$metadata_html<dd><a target=\"_blank\" href=\"/$(TARGET_ROOT)$(link)\">$link</a></dd></dl>"
                    end,
                    keys_sorted
                ),
                "\n"
        ))
        </main>
    ")
end

serve(; host="0.0.0.0", port=PORT)
