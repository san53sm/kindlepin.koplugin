local ButtonTable = require("ui/widget/buttontable")
local ImageViewer = require("ui/widget/imageviewer")
local _ = require("pinlocale")

local ImageViewerHook = {}

function ImageViewerHook.install(get_active_plugin)
    if ImageViewer._kindlepin_hooked then
        return
    end
    ImageViewer._kindlepin_hooked = true

    local orig_init = ImageViewer.init
    ImageViewer.init = function(viewer)
        local orig_new = ButtonTable.new
        ButtonTable.new = function(class, options)
            local plugin = get_active_plugin and get_active_plugin()
            -- Document images are passed as blitbuffers (`image`), not files.
            if plugin
                and viewer.image
                and not viewer.file
                and options
                and options.buttons
            then
                table.insert(options.buttons, 1, {
                    {
                        id = "kindlepin",
                        text = _("Pin"),
                        callback = function()
                            plugin:pinFromImageViewer(viewer)
                        end,
                    },
                })
            end
            return orig_new(class, options)
        end
        local ok, err = pcall(orig_init, viewer)
        ButtonTable.new = orig_new
        if not ok then
            error(err)
        end
    end
end

return ImageViewerHook
