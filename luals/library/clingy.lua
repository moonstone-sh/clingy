---@meta clingy
--- Clingy v0 LuaCATS Library Definitions
--- Declarative CLI Engine for Lua

---@class standard_schema.Props<I, O>
---@field version 1
---@field vendor string
---@field validate fun(value: any, options?: table): { value?: O, issues?: table[] }
---@field types? { input: I, output: O }

---@class standard_schema.Schema<I, O>
---@field ["~standard"] standard_schema.Props<I, O>

---@alias StandardSchema<I, O> standard_schema.Schema<I, O>
---@alias clingy.StandardSchema<I, O> standard_schema.Schema<I, O>

---@class clingy.Binding<O>
---@field _tag "declaration"
---@field kind "arg"|"option"|"flag"|"define"|"passthrough"
---@field name? string
---@field names? string[]
---@field result_key string
---@field schema? any
---@field occurrence { min: integer?, max: integer? }
---@field values { min: integer, max: integer? }
---@field aggregate "scalar"|"array"
---@field default? any

---@class clingy.CommandNode
---@field _tag "node"
---@field declarations table
---@field children table<string, clingy.CommandNode>
---@field metadata table

---@class clingy.CommandGraph
---@field format "clingy.command-graph.v0"
---@field name string
---@field version string
---@field description? string
---@field root string
---@field nodes table<string, table>
---@field bindings table<string, table>

---@class clingy.CompiledRouter
---@field format "clingy.compiled-router.v0"
---@field name string
---@field version string
---@field graph clingy.CommandGraph
---@field root table
---@field nodes table<string, table>

---@class clingy.PresentationHost
---@field start? fun(self: clingy.PresentationHost, invocation: { invocation_id: string, app_name: string, version?: string, argv: string[] })
---@field handle_event fun(self: clingy.PresentationHost, event: table)
---@field flush? fun(self: clingy.PresentationHost)
---@field suspend? fun(self: clingy.PresentationHost, reason?: string)
---@field resume? fun(self: clingy.PresentationHost)
---@field prompt? fun(self: clingy.PresentationHost, request: { type?: "confirm"|"text", prompt: string, default?: any, timeout_ms?: integer }): any
---@field finish? fun(self: clingy.PresentationHost, result: { status: "ok"|"failed"|"interrupted"|"terminated", exit_code: integer, error?: any })
---@field close? fun(self: clingy.PresentationHost)

---@class clingy.ComposerOptions
---@field mode? "auto"|"fancy"|"plain"|"quiet"|"ndjson"|"json"
---@field stdout? any
---@field stderr? any
---@field is_tty? boolean
---@field capture? boolean

---@class clingy.App
---@field _graph clingy.CompiledRouter
---@field _config table
local App = {}

---Returns the normalized Command Graph IR.
---@return clingy.CommandGraph
function App:graph() end

---Generates formatted help text for a target node or subcommand path.
---@param node_or_path? string|string[]|table
---@return string
function App:help(node_or_path) end

---Parses argv without executing handlers.
---@param argv? string[]
---@return { target_node: table, route: table[], args: table<string, any>, passthrough: string[] }
function App:parse(argv) end

---Executes full CLI lifecycle against argv.
---@param argv? string[]
---@param opts? { presentation?: clingy.PresentationHost, composer?: clingy.PresentationHost, composer_mode?: "auto"|"fancy"|"plain"|"quiet"|"ndjson"|"json", stdout?: any, stderr?: any, is_tty?: boolean, capture?: boolean }
---@return integer
function App:run(argv, opts) end

---Dispatches a signal to the active node.
---@param sig string|integer
---@param ctx? clingy.Context<any>
---@return boolean
function App:handle_signal(sig, ctx) end

---Executes completion query against the application router.
---@param req { words?: string[], cword?: integer }|string[]
---@return clingy.CompletionResponse
function App:complete(req) end

---Generates shell completion integration script.
---@param shell "bash"|"zsh"|"fish"|"powershell"
---@param cmd_path? string
---@return string
function App:completion_script(shell, cmd_path) end

---@class clingy.Scope
---@field parent? clingy.Scope
---@field context clingy.Context<any>
---@field state "active"|"unwinding"|"unwound"
local Scope = {}

---Registers a cleanup function to be executed in LIFO order on scope exit.
---@param fn fun(reason: "success"|"error"|"interrupt"|"terminate", err?: any)
function Scope:defer(fn) end

---Manually unwinds all deferred actions in this scope.
---@param reason? "success"|"error"|"interrupt"|"terminate"
---@param err? any
function Scope:unwind(reason, err) end

---@class clingy.ManagedProcess
---@field id string
---@field argv string[]
---@field state "declared"|"spawning"|"running"|"draining"|"terminating"|"killed"|"reaped"
---@field pid? integer
---@field exit_code? integer
local ManagedProcess = {}

---Waits for process completion and reaps exit code.
---@return integer exit_code
---@return string stdout
---@return string stderr
function ManagedProcess:wait() end

---Sends a signal to the child process.
---@param sig string|integer
function ManagedProcess:kill(sig) end

---Sends a structured control IPC message to the child process.
---@param msg table
function ManagedProcess:send_ipc(msg) end

---@generic A
---@class clingy.Context<A>
---@field args A Parsed and validated argument table
---@field route { node: string, node_ir?: table, args: table<string, any> }[] Linear list of matched route segments
---@field passthrough string[] Captured tokens following '--'
---@field target_node table Matched compiled command node
---@field bus any Semantic event bus
---@field presentation clingy.PresentationHost Canonical Presentation Host instance
---@field composer clingy.PresentationHost @deprecated Use ctx.presentation instead; transitional compatibility alias
---@field app clingy.App Enclosing CLI application instance
local Context = {}

---Retrieves a validated argument value by declaration Binding handle or string key.
---@generic O
---@param binding clingy.Binding<O>
---@return O
---@overload fun(self: clingy.Context<any>, key: string): any
function Context:get(binding) end

---Creates a structured resource scope with deterministic LIFO defer unwind.
---@generic R
---@param fn fun(scope: clingy.Scope): R
---@return R
function Context:scope(fn) end

---Spawns a managed child subprocess.
---@param opts { argv: string[], cwd?: string, env?: table<string, string>, mode?: "capture"|"inherit"|"interactive"|"protocol", timeout_ms?: integer }
---@return clingy.ManagedProcess
function Context:spawn(opts) end

---Creates an execution span for telemetry and events.
---@generic R
---@param name string
---@param fn? fun(span_id: string): R
---@return R|string
function Context:span(name, fn) end

---Emits a progress event.
---@param task string
---@param percent integer 0..100
---@param msg? string
function Context:progress(task, percent, msg) end

---Emits a milestone event.
---@param msg string
function Context:milestone(msg) end

---Emits a structured log event.
---@param level? "debug"|"info"|"warn"|"error"
---@param msg string
---@param metadata? table
function Context:log(level, msg, metadata) end

---Emits a result event.
---@param data any
---@param msg? string
function Context:result(data, msg) end

---Marks execution failure with custom message or exit code.
---@param msg_or_err string|any
---@param exit_code? integer
function Context:fail(msg_or_err, exit_code) end

---Prompts user for interactive confirmation via Composer.
---@param prompt string
---@param opts? { default?: boolean, timeout_ms?: integer }
---@return boolean
function Context:confirm(prompt, opts) end

---@class clingy
---@field tail fun(name: string, terminator: string, opts: { [1]: clingy.ForwardPolicy }): clingy.EndDeclaration
local c = {}

---Compiles a declarative CLI specification into an executable App.
---@param config { [1]?: table, root?: table|clingy.CommandNode, name?: string, version?: string, description?: string, mode?: "auto"|"fancy"|"plain"|"quiet"|"json" }
---@return clingy.App
function c.create(config) end

---Declares the root command node for `c.create`.
---@param node clingy.CommandNode
---@return table
function c.root(node) end

---Defines a command node in the CLI router tree.
---@param children_and_decls table Array of declarations and string-keyed child nodes
---@param metadata? { description?: string, aliases?: string[], hidden?: boolean }
---@return clingy.CommandNode
function c.node(children_and_decls, metadata) end

---Reusable grammar fragment for composition.
---@param declarations table Array of declarations
---@return table
function c.group(declarations) end

---Explicit downward inheritance wrapper.
---@param ... any Declarations, groups, or parser modes to inherit downward
---@return table
function c.inherit(...) end

---@class clingy.Literal
---@field _tag "form_literal"
---@field text string

---@class clingy.ForwardPolicy
---@field _tag "forward"
---@field mode "trimmed"|"complete"

---@class clingy.EndDeclaration
---@field _tag "end"
---@field result_key string
---@field terminator string
---@field forward "trimmed"|"complete"

---@class clingy.Occurs
---@field min? integer
---@field max? integer|"many"

---@class clingy.ArgOptions<O>
---@field key string
---@field schema? standard_schema.Schema<any, O>
---@field form? table
---@field occurs? clingy.Occurs
---@field complete? clingy.CompletionProvider

---@class clingy.OptionOptions<O>
---@field key string
---@field aliases string[]
---@field value? { schema?: standard_schema.Schema<any, O>, attached?: string[], detached?: boolean, adjacent?: boolean }
---@field form? table
---@field occurs? clingy.Occurs
---@field complete? table

---@class clingy.FlagOptions
---@field key string
---@field aliases string[]
---@field occurs? clingy.Occurs
---@field complete? table

---@generic O
---@param opts clingy.ArgOptions<O>
---@return clingy.Binding<O>
function c.arg(opts) end

---@generic O
---@param opts clingy.OptionOptions<O>
---@return clingy.Binding<O>
function c.option(opts) end

---@param opts clingy.FlagOptions
---@return clingy.Binding<boolean>
function c.flag(opts) end

---@param opts { key: string, schema?: any, complete?: table }
---@return table
function c.capture(opts) end

---@param opts { text: string }
---@return table
function c.literal(opts) end

---@param parts table[]
---@return table
function c.sequence(parts) end

---@param parts table[]
---@return table
function c.choice(parts) end

---@return table
function c.next_token() end

---@param atom table
---@return table
function c.optional(atom) end

---Parser mode: interspersed (default). Visible options/flags may appear between positionals.
---@return table
function c.interspersed() end

---Parser mode: leading. Options/flags must precede positionals in segment.
---@return table
function c.leading() end

---Parser mode: ordered. Declarations must be matched in declared order.
---@return table
function c.ordered() end

---Parser capability: short flag clustering (e.g. -xfv -> -x -f -v).
---@return table
function c.short_clusters() end

---Declares a passthrough capture key for tokens following '--'.
---@param key? string
---@return clingy.Binding<string[]>
function c.passthrough(key) end

---Selects how c.tail forwards its terminator and remaining tokens.
---@param mode "trimmed"|"complete"
---@return clingy.ForwardPolicy
function c.forward(mode) end

---Declares a node tail marker and raw token capture.
---@param name string
---@param terminator string
---@param opts { [1]: clingy.ForwardPolicy }
---@return clingy.EndDeclaration
function c.tail(name, terminator, opts) end

---Declares the execution handler for a command node.
---@param fn fun(ctx: clingy.Context<table<string, any>>): any
---@return table
function c.run(fn) end

---Declares signal handlers for a command node.
---@param handlers table<string, fun(ctx: clingy.Context<any>, sig: string): any>
---@return table
function c.signals(handlers) end

---Predefined signal handler action constructors.
c.signal = {
  ---@param opts? { grace_period_ms?: integer }
  ---@return table
  shutdown = function(opts) end,
}

---Declares a custom lifecycle stage extension.
---@param stage_def { id: string, before?: string, after?: string, run?: fun(ctx: clingy.Context<any>) }
---@return table
function c.stage(stage_def) end

---@class clingy.SchemaAdapter
---@field vendor string
---@field match fun(schema: any): boolean
---@field inspect? fun(schema: any): { kind?: string, description?: string, default?: any, options?: string[] }
---@field coerce? fun(schema: any, token: string): any

---Registers a custom schema adapter for third-party validation libraries.
---@param adapter clingy.SchemaAdapter
function c.schema_adapter(adapter) end

---@class clingy.CompletionCandidate
---@field value string
---@field description? string
---@field display? string
---@field directive? integer

---@class clingy.CompletionFilesystem
---@field kind "path"|"file"|"directory"
---@field extensions string[]

---@class clingy.CompletionResponse
---@field candidates clingy.CompletionCandidate[]
---@field directive integer
---@field filesystem? clingy.CompletionFilesystem
---@field replace_prefix string
---@field add fun(self: clingy.CompletionResponse, val_or_table: string|table, description?: string, directive?: integer): clingy.CompletionResponse
---@field add_directive fun(self: clingy.CompletionResponse, flag: integer): clingy.CompletionResponse
---@field has_directive fun(self: clingy.CompletionResponse, flag: integer): boolean
---@field set_filesystem fun(self: clingy.CompletionResponse, kind: "path"|"file"|"directory", opts?: { extensions?: string[] }): clingy.CompletionResponse
---@field filter_by_prefix fun(self: clingy.CompletionResponse, prefix?: string): clingy.CompletionResponse
---@field sort fun(self: clingy.CompletionResponse): clingy.CompletionResponse

---@class clingy.CompletionContext
---@field args table
---@field prefix string
---@field route table[]
---@field target_node? table
---@field binding? table
---@field cwd string
---@field env table<string, string>
---@field words string[]
---@field cword integer

---@class clingy.CompletionProvider
---@field _tag "completion_provider"
---@field kind "values"|"path"|"file"|"directory"|"dynamic"|"none"
---@field resolve fun(self: clingy.CompletionProvider, ctx: clingy.CompletionContext): clingy.CompletionResponse

---Constructs a static values completion provider.
---@param ... string|table|string[] List of values or candidate tables
---@return clingy.CompletionProvider
function c.values(...) end

---Constructs a generic path completion provider.
---@param opts? table
---@return clingy.CompletionProvider
function c.path(opts) end

---Constructs a file completion provider.
---@param opts? { extensions?: string[] }
---@return clingy.CompletionProvider
function c.file(opts) end

---Constructs a directory completion provider.
---@param opts? table
---@return clingy.CompletionProvider
function c.directory(opts) end

---Constructs a dynamic callback completion provider.
---@param fn fun(ctx: clingy.CompletionContext): clingy.CompletionResponse|clingy.CompletionCandidate[]|string[]
---@return clingy.CompletionProvider
function c.dynamic(fn) end

---Constructs a hard suppression completion provider.
---@return clingy.CompletionProvider
function c.none() end

---Presentation host subsystem and constructors.
c.presentation = {}

---Constructs a default Composer Presentation Host.
---@param opts? clingy.ComposerOptions
---@return clingy.PresentationHost
function c.composer(opts) end

---Constructs a NullHost for silent execution.
---@return clingy.PresentationHost
function c.null_host() end

---Constructs a RecordingHost for test inspection.
---@param opts? { prompt_responses?: (any[]|fun(req: table): any) }
---@return clingy.PresentationHost
function c.recording_host(opts) end

---Constructs a FailingHost for fault injection testing.
---@param opts? { fail_on?: table<string, string> }
---@return clingy.PresentationHost
function c.failing_host(opts) end

return c
