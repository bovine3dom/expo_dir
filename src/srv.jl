#!/bin/julia

using Oxygen, JSON
using Humanize: datasize

PORT = get(ENV, "JULIA_API_PORT", 1989)

DIRECTORY = "/mnt/chungus/expo/data/"

TARGET_ROOT = "expo/?data="

css = join(readlines("$(@__DIR__)/src/simple.css"), "\n")

function get_trouvailles()
    trouvailles = Dict()
    for (root, dirs, files) in walkdir(DIRECTORY)
        for file in files
            extension = splitext(file)[2][2:end]
            # CSV files: key without extension
            # Arrow/parquet/geojson: key with extension
            if extension == "csv"
                key = joinpath(root, splitext(file)[1])[length(DIRECTORY)+1:end]
            else
                key = joinpath(root, file)[length(DIRECTORY)+1:end]
            end
            trouvailles[key] = get(trouvailles, key, Dict())
            trouvailles[key][extension] = joinpath(root, file)
        end
    end

    for (k,v) in trouvailles
        for (extension,filepath) in v
            if extension == "json"
                trouvailles[k]["metadata"] = JSON.parsefile(filepath)
            end
        end
    end

    for (k,v) in trouvailles
        for (extension,filepath) in v
            if extension in ["csv", "arrow", "parquet", "geojson"]
                trouvailles[k]["filesize"] = datasize(filesize(filepath))
            end
        end
    end

    for (k,v) in trouvailles
        for (extension,filepath) in v
            if extension in ["csv", "arrow", "parquet", "geojson"]
                trouvailles[k]["modified"] = mtime(filepath)
            end
        end
    end

    # Delete entries without any supported data format
    supported_formats = ["csv", "arrow", "parquet", "geojson"]
    filter!(trouvailles) do (k, v)
        !isempty(intersect(keys(v), supported_formats))
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
                        desc = get(get(trouvailles[x], "metadata", Dict("t" => x)), "t", x)
                        bigness = get(trouvailles[x], "filesize", "")
                        return "<div><dt>$desc, $bigness</dt> <dd><a target=\"_blank\" href=\"/$(TARGET_ROOT)$(x)\">$x</a></dd></div><br>"
                    end,
                    keys_sorted
                ),
                "\n"
        ))
        </main>
    ")
end

serve(; host="0.0.0.0", port=PORT)
