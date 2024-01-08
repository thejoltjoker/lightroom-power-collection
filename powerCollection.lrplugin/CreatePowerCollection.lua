-- InitPlugin.lua
local LrApplication = import "LrApplication"
local LrBinding = import "LrBinding"
local LrDialogs = import "LrDialogs"
local LrTasks = import "LrTasks"
local LrFunctionContext = import "LrFunctionContext"
local LrLogger = import "LrLogger"
local LrView = import "LrView"
local logger = LrLogger("PowerCollectionLogger")
logger:enable("logfile") -- Logs to ~/Library/Application Support/Adobe/Lightroom/Modules

local function toCamelCase(str)
    -- Split the string into words based on spaces or underscores
    local words = {}
    for word in string.gmatch(str, "[^%s_]+") do
        table.insert(words, word:lower())
    end

    -- Capitalize the first letter of each word (except the first one)
    for i = 2, #words do
        words[i] = words[i]:sub(1, 1):upper() .. words[i]:sub(2)
    end

    -- Concatenate the words to form camelCase
    return table.concat(words)
end

local function lightroomTimestampToUnix(timestamp)
    local unixTimestamp = timestamp + os.time({
        year = 2001,
        month = 1,
        day = 1,
        hour = 0,
        min = 0,
        sec = 0
    })
    return unixTimestamp
end

-- Main function to be called when the plugin is initialized
local function main()
    logger:info("Initializing Your Lightroom Plugin")

    local catalog = LrApplication.activeCatalog()
    local targetPhotos = catalog:getTargetPhotos()

    -- Get datetime prefix from first selected photo
    local dateTime = targetPhotos[1]:getRawMetadata("dateTime")

    local unixTimestamp = os.time()

    if dateTime and dateTime ~= '' then
        unixTimestamp = lightroomTimestampToUnix(dateTime)
    end

    -- Use capture date from photo as prefix or set today
    local captureDatePrefix = os.date("%y%m", unixTimestamp)

    -- Get title from photo or set a default
    local title = targetPhotos[1]:getFormattedMetadata("title")
    if not title or title == '' then
        title = 'name'
    else
        title = toCamelCase(title)
    end

    -- Display a dalog box
    LrFunctionContext.callWithContext("showPowerCollectionDialog", function(context)
        local props = LrBinding.makePropertyTable(context)
        props.name = captureDatePrefix .. "_" .. title
        props.apply = true

        local f = LrView.osFactory()

        -- Create the contents for the dialog.
        local c = f:column{
            bind_to_object = props,
            spacing = f:control_spacing(),

            f:row{f:static_text{
                title = "Name: "
            }, f:edit_field{
                width_in_chars = "30",
                enabled = true,
                value = LrView.bind("name")
            }},
            f:row{f:checkbox{
                title = "Apply to selected photos",
                enabled = true,
                value = LrView.bind("apply")
            }}
        }

        -- Show window
        local result = LrDialogs.presentModalDialog {
            title = "Create Power Collection",
            contents = c
        }

        if result == "ok" then
            -- Get publish service
            local name = "_" .. props.name
            local service = nil
            local services = catalog:getPublishServices()

            -- Find the publish service called photos
            for i = 1, #services do
                if services[i]:getName() == "photos" then
                    logger:info("Publish service found")
                    service = services[i]
                end
            end
            if service == nil then
                logger:info("Publish service not found")
                LrDialogs.message("Create Power Collection", 'No publish service called "photos" found', "info")
            end

            -- Create keyword tag inside _collections
            local collectionsKeyword = nil
            catalog:withWriteAccessDo("Create _collections keyword", function()
                collectionsKeyword = catalog:createKeyword('_collection', nil, false, nil, true)
            end)

            local keyword = nil
            catalog:withWriteAccessDo("Create keyword", function()
                keyword = catalog:createKeyword(name, nil, false, collectionsKeyword, true)
            end)

            -- Add keyword to photos
            if props.apply then
                catalog:withWriteAccessDo("Add keyword to photos", function()
                    for i = 1, #targetPhotos do
                        targetPhotos[i]:addKeyword(keyword)
                    end
                end)
            end

            -- Set search params for the collection
            local searchDesc = {{
                criteria = "keywords",
                operation = "any",
                value = name
            }, {
                criteria = "rating",
                operation = ">=",
                value = 1
            }, {
                criteria = "labelColor",
                operation = "==",
                value = 3 -- Green color label
            }, {
                criteria = "title",
                operation = "notEmpty"
            }}

            -- Create published smart collection 
            local publishedCollection = nil
            catalog:withWriteAccessDo("Create published smart collection", function()
                publishedCollection = service:createPublishedSmartCollection(props.name, searchDesc, nil, true)
            end)

            -- Create smart collection
            local collection = nil
            local collectionSet = nil

            -- Update searchDesc for smart collection
            searchDesc = {{
                criteria = "keywords",
                operation = "any",
                value = name
            }}

            catalog:withWriteAccessDo("Create smart collection", function()
                collectionSet = catalog:createCollectionSet('_collection', nil, true)
                collection = catalog:createSmartCollection(props.name, searchDesc, collectionSet, true)
            end)

            local msg = string.format("Power collection %q created.", name)
            LrDialogs.message("Create Power Collection", msg, "info")
        end
    end)
end

-- run main()
LrTasks.startAsyncTask(main)
