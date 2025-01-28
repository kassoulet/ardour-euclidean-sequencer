ardour({
    ["type"] = "dsp",
    name = "Euclidean Sequencer",
    category = "Effect",
    author = "Gautier Portet",
    license = "MIT",
    description = [[euclidean_sequencer v0.2

Simple euclidean sequencer.
]],
})

-- Copyright (c) Gautier Portet, MIT License
-- Implementing https://en.wikipedia.org/wiki/Euclidean_rhythm
--
local debug = false

function dsp_ioconfig()
    return { { midi_in = 1, midi_out = 1, audio_in = -1, audio_out = -1 } }
end

function dsp_options()
    return { time_info = true, regular_block_length = true }
end

function dsp_params()
    return {
        {
            type = "input",
            name = "Events",
            min = 1,
            max = 24,
            default = 4,
            integer = true,
            doc = "number of events to generate",
        },
        {
            type = "input",
            name = "Steps",
            min = 1,
            max = 24,
            default = 16,
            integer = true,
            doc = "total number of subdivisions of the beat",
        },
        {
            type = "input",
            name = "Offset",
            min = 0,
            max = 24,
            default = 0,
            integer = true,
            doc = "shift events",
        },
        {
            type = "input",
            name = "Note Gate",
            min = 0,
            max = 4,
            default = 1,
            doc = "note duration as a fraction of a step",
            scalepoints = {
                ["1/4"] = 4,
                ["1/8"] = 2,
                ["1/16"] = 1,
                ["1/32"] = 0.5,
                ["1/64"] = 0.25,
            },
        },
        {
            type = "input",
            name = "Note",
            min = 1,
            max = 12,
            default = 1,
            integer = true,
            doc = "note",
            scalepoints = {
                ["C"] = 1,
                ["C#"] = 2,
                ["D"] = 3,
                ["D#"] = 4,
                ["E"] = 5,
                ["F"] = 6,
                ["F#"] = 7,
                ["G"] = 8,
                ["G#"] = 9,
                ["A"] = 10,
                ["A#"] = 11,
                ["B"] = 12,
            },
        },
        {
            type = "input",
            name = "Octave",
            min = 0,
            max = 8,
            default = 3,
            integer = true,
            doc = "octave",
        },
        {
            type = "input",
            name = "Velocity",
            min = 0,
            max = 127,
            default = 100,
            integer = true,
            doc = "note velocity",
        },
        {
            type = "input",
            name = "Step Duration",
            min = 1,
            max = 64,
            default = 16,
            integer = true,
            doc = "step duration as fraction of a beat",
            scalepoints = {
                ["1/1"] = 1,
                ["1/2"] = 2,
                ["1/4"] = 4,
                ["1/8"] = 8,
                ["1/16"] = 16,
                ["1/32"] = 32,
                ["1/64"] = 64,
            },
        },
    }
end

function presets()
    -- from http://cgm.cs.mcgill.ca/~godfried/publications/banff.pdf
    return
    {
        { name = "Cuban Drum - E(2,3)",         params = { Events = 2, Steps = 3 , Offset = 0 } },
        { name = "Cumbia - E(3,4)",             params = { Events = 3, Steps = 4, Offset = 0  } },
        { name = "Khafif-e-ramal - E(2,5)",     params = { Events = 2, Steps = 5, Offset = 0  } },
        { name = "Bulgarian Folk - E(3,7)",     params = { Events = 3, Steps = 7, Offset = 0  } },
        { name = "Ruchenitza - E(4,7)",         params = { Events = 4, Steps = 7, Offset = 0  } },
        { name = "York-Samai - E(5,6)",         params = { Events = 5, Steps = 6, Offset = 0  } },
        { name = "Nawakhat - E(5,7)",           params = { Events = 5, Steps = 7, Offset = 0  } },
        { name = "Cuban tresillo - E(3,8)",     params = { Events = 3, Steps = 8, Offset = 0  } },
        { name = "Cuban cinquillo - E(5,8)",    params = { Events = 5, Steps = 8, Offset = 0  } },
        { name = "Tuareg - E(7,8)",             params = { Events = 7, Steps = 8, Offset = 0  } },
        { name = "Aksak - E(4,9)",              params = { Events = 4, Steps = 9, Offset = 0  } },
        { name = "Agsag-Samai - E(5,9)",        params = { Events = 5, Steps = 9, Offset = 0  } },
        { name = "Outside Now - E(4,11)",        params = { Events = 4, Steps = 11, Offset = 0  } },
        { name = "Fandango - E(4,12)",           params = { Events = 4, Steps = 12, Offset = 0  } },
        { name = "Venda - E(5,12)",              params = { Events = 5, Steps = 12, Offset = 0  } },
        { name = "Mpre - E(7,12)",               params = { Events = 7, Steps = 12, Offset = 0  } },
        { name = "Four on the floor - E(4,16)",  params = { Events = 4, Steps = 16, Offset = 0  } },
        { name = "Brazilian Necklace - E(5,16)", params = { Events = 5, Steps = 16, Offset = 0  } },
        { name = "Samba - E(7,16)",              params = { Events = 7, Steps = 16, Offset = 0  } },
        { name = "Ngbaka-Maibo - E(9,16)",       params = { Events = 9, Steps = 16, Offset = 0  } },
        { name = "Aka 1 - E(11,24)",              params = { Events = 11, Steps =24, Offset = 0  } },
        { name = "Aka 2 - E(13,24)",              params = { Events = 13, Steps =24, Offset = 0  } },
    }
end

local spb = 0          -- samples per beat
local current_step = 0 -- step counter
local previous_params = {}
local previous_note_index = -1
local current_note_stop = -1

function dsp_init(rate)
    local bpm = 120
    spb = rate * 60 / bpm -- XXX
    if spb < 2 then
        spb = 2
    end
    -- Shared memory 0 -> current step 1 -> rolling 2 -> midinote
    self:shmem():allocate(3)
    -- set rolling to false
    local rolling = Session:transport_state_rolling() and 1 or 0 -- to_int
    self:shmem():atomic_set_int(0, current_step)
    self:shmem():atomic_set_int(1, rolling)
end

-- retuns events, steps, offset, step_duration
local function read_params()
    local ctrl = CtrlPorts:array()
    return math.floor(ctrl[1]), math.floor(ctrl[2]), math.floor(ctrl[3]), math.floor(ctrl[8])
end

-- returns note, octave, volume, note_duration
local function read_noteinfo()
    local ctrl = CtrlPorts:array()
    return math.floor(ctrl[5]), math.floor(ctrl[6]), math.floor(ctrl[7]), ctrl[4]
end

-- Euclidean rythm (http://en.wikipedia.org/wiki/Euclidean_Rhythm)
-- https://rosettacode.org/wiki/Euclidean_rhythm#Lua
local function euclidean_rhythm(k, n)
    local s = {}
    for i = 1, n do
        if i <= k then
            table.insert(s, { true })
        else
            table.insert(s, { false })
        end
    end

    local d = n - k
    n = math.max(k, d)
    k = math.min(k, d)
    local z = d

    while z > 0 or k > 1 do
        for i = 1, k do
            for _, v in ipairs(s[#s - i + 1]) do
                table.insert(s[i], v)
            end
        end
        for _ = 1, k do
            table.remove(s)
        end
        z = z - k
        d = n - k
        n = math.max(k, d)
        k = math.min(k, d)
    end

    local result = {}
    for _, sublist in ipairs(s) do
        for _, item in ipairs(sublist) do
            table.insert(result, item)
        end
    end

    return result
end

function dsp_run(_, _, n_samples)
    assert(type(midiin) == "table")
    assert(type(midiout) == "table")
    assert(type(time) == "table")
    assert(spb > 1)

    local m = 1
    local events, steps, offset, step_duration = read_params()
    local note, octave, volume, duration = read_noteinfo()

    local rolling = Session:transport_state_rolling() and 1 or 0 -- to_int
    local sequence = euclidean_rhythm(events, steps)

    local subdiv = 1
    local denom = time.ts_denominator * subdiv
    local ts = time.sample
    local bt = time.beat
    local tm = Temporal.TempoMap.read()
    local pos = Temporal.timepos_t(ts)
    local bbt = tm:bbt_at(pos)
    local meter = tm:meter_at(pos)
    local tempo = tm:tempo_at(pos)

    for _, ev in ipairs(midiin) do
        -- pass through all MIDI data
        if debug > 0 then
            local status, num, val = table.unpack(ev.data)
            local ch = status & 0xf
            status = status & 0xf0
            if debug then
                print(string.format("midithru: msg:%x ch:%x %x,%x", status, ch, num, val))
            end
        end
        midiout[m] = ev
        m = m + 1
    end

    if rolling > 0 then
        for time = 0, n_samples - 1 do
            local current_note_index = math.floor(((ts + time) / spb) * step_duration / 4)
            current_note_index = math.max(0, current_note_index)

            if current_note_index ~= previous_note_index then
                current_step = current_note_index % steps
                local active_step = sequence[1 + (current_step + offset) % #sequence]

                if active_step then
                    -- note on
                    local midinote = note - 1 + (octave + 1) * 12
                    midiout[m] = {}
                    if ts + time < 0 then
                        time = -(ts + time)
                    end

                    midiout[m]["time"] = time
                    midiout[m]["data"] = { 0x90, midinote, volume }
                    m = m + 1
                    self:shmem():atomic_set_int(2, midinote)
                    -- send note off after duration
                    local note_duration = math.floor(duration * spb / 4)
                    current_note_stop = ts + time + note_duration
                    if debug then
                        print(string.format("*** noteon  %s - start: %d - stop: %d - duration: %d",
                            bbt:str(), ts + time, current_note_stop, note_duration))
                    end
                end
                previous_note_index = current_note_index
            end

            if current_note_stop > 0 and (ts + time) >= current_note_stop then
                -- note off
                if debug then
                    print(string.format("*** noteoff %s - stop: %d - stop: %d",
                        bbt:str(), ts + time, current_note_stop))
                end
                local midinote = self:shmem():atomic_get_int(2)
                if midinote > 0 then
                    self:shmem():atomic_set_int(2, 0)
                    midiout[m] = {}
                    midiout[m]["time"] = time
                    midiout[m]["data"] = { 0x80, midinote, 0 }
                    m = m + 1
                end
                current_note_stop = 0
            end
        end
    end
    -- update ui ?
    local params = { events, steps, offset, current_step, rolling }
    if table.concat(params) ~= table.concat(previous_params) then
        -- Share current step and rolling state with inline UI
        self:shmem():atomic_set_int(0, current_step)
        self:shmem():atomic_set_int(1, rolling)
        -- Push redraw event
        self:queue_draw()

        if debug then
            print(string.format("%s- %d - %g [%d] - %d/%d - %g bpm - rolling: %s", bbt:str(),
                current_step,
                math.floor(denom * bt) / denom, ts - 1,
                meter:divisions_per_bar(), meter:note_value(),
                tempo:quarter_notes_per_minute(), rolling))
        end
    end
    previous_params = params
end

function render_inline(ctx, w, _max_h) -- inline display
    local h = w

    local events, steps, offset, _ = read_params()
    local sequence = euclidean_rhythm(events, steps)
    local pos = self:shmem():atomic_get_int(0)
    local rolling = self:shmem():atomic_get_int(1)

    -- draw background
    ctx:rectangle(0, 0, w, h)
    ctx:set_source_rgba(.2, .2, .2, 1.0)
    ctx:fill()
    ctx:set_line_width(1.5)
    ctx:set_source_rgba(1, 1, 1, 1)

    -- draw sequence
    local r = w * 0.4
    local c = w * 0.05
    local cx = w / 2
    local cy = h / 2

    for i = 0, steps - 1 do
        local x = cx + r * math.cos(2 * math.pi * (i / steps) - 0.5 * math.pi)
        local y = cy + r * math.sin(2 * math.pi * (i / steps) - 0.5 * math.pi)
        ctx:arc(x, y, c, 0, 2 * math.pi)
        local active = sequence[(i + 1 + offset) % #sequence]
        if active then
            ctx:set_line_width(2)
            ctx:set_source_rgba(1, 1, 1, 1)
        else
            ctx:set_line_width(1)
            ctx:set_source_rgba(1, 1, 1, 0.7)
        end
        if i == pos and rolling > 0 then
            ctx:fill()
        else
            ctx:stroke()
        end
    end
    return { w, h }
end
