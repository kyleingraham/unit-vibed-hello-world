import std.concurrency : ownerTid, receive, receiveOnly, spawn, thisTid;
import std.format : format;
import std.string : toStringz;
import unit_integration;
import vibe.core.concurrency : send;
import vibe.core.core : exitEventLoop, runApplication, runTask;
import vibe.core.task : Task;

shared Task dispatchTask;

int main(string[] args)
{
    // Run Unit's event loop in a separate thread.
    spawn((){
        int rc;
        nxt_unit_init_t init;
        init.callbacks.request_handler = &(unitRequestHandler);
        init.callbacks.ready_handler = &(unitReadyHandler);
        nxt_unit_ctx_t* unitContext = nxt_unit_init(&init);
        if (unitContext is null)
        {
            logUnit(
                null,
                UnitLogLevel.alert,
                "Failed to initialize NGINX Unit context"
            );
            rc = NXT_UNIT_ERROR;
            goto fail;
        }

        logUnit(null, UnitLogLevel.debug_, "Unit starting");
        rc = nxt_unit_run(unitContext);
        nxt_unit_done(unitContext);

        fail:
        send(dispatchTask, CancelMessage());
        send(ownerTid, rc);
    });

    // Run our request handler as a task in the main thread.
    dispatchTask = runTask(() nothrow {
        bool shouldRun = true;
        logUnit(null, UnitLogLevel.debug_, "Dispatch task started");

        while (shouldRun)
        {
            try
            {
                void requestInfoHandler(RequestInfoMessage message)
                {
                    dispatch(message);
                }

                void cancelHandler(CancelMessage message)
                {
                    shouldRun = false;
                }

                receive(&requestInfoHandler, &cancelHandler);
            }
            catch (Exception e)
            {
                logUnit(null, UnitLogLevel.alert, e.msg);
                shouldRun = false;
            }
        }

        exitEventLoop();
    });

    runApplication();

    return receiveOnly!int;
}

struct RequestInfoMessage
{
    shared nxt_unit_request_info_t* requestInfo;
}

struct CancelMessage{}

void dispatch(RequestInfoMessage message)
{
    debug(Concurrency)
    {
        import core.time : msecs;
        import vibe.core.core : sleep;
    }

    runTask((nxt_unit_request_info_t* requestInfo) {
        try
        {
            ushort statusCode = 200;
            auto response = "Hello, World!\n";
            auto contentType = ["Content-Type", "text/plain"];

            debug(Concurrency)
            {
                sleep(10.msecs); // Test that vibe.d's concurrency system works.
            }

            auto rc = nxt_unit_response_init(
                requestInfo,
                statusCode,
                cast(uint)1,
                cast(uint)(
                  contentType[0].length +
                  contentType[1].length +
                  response.length
                )
            );
            if (rc != NXT_UNIT_OK)
                goto fail;

            rc = nxt_unit_response_add_field(
                requestInfo,
                contentType[0].toStringz,
                cast(ubyte)contentType[0].length,
                contentType[1].toStringz,
                cast(uint)contentType[1].length
            );
            if (rc != NXT_UNIT_OK)
                goto fail;

            rc = nxt_unit_response_add_content(
                requestInfo,
                response.toStringz,
                cast(uint)response.length
            );
            if (rc != NXT_UNIT_OK)
                goto fail;

            rc = nxt_unit_response_send(requestInfo);
            if (rc != NXT_UNIT_OK)
                goto fail;

            fail:
            nxt_unit_request_done(requestInfo, rc);
        }
        catch (Exception e)
        {
            logUnit(null, UnitLogLevel.alert, e.msg);
        }
    }, cast(nxt_unit_request_info_t*)message.requestInfo);
}

extern(C)
void unitRequestHandler(nxt_unit_request_info_t* requestInfo)
{
    // Here we will be in the Unit thread and will need to send a
    // message back to the main thread.

    auto sharedRequestInfo = cast(shared)requestInfo;
    auto message = RequestInfoMessage(sharedRequestInfo);

    send(dispatchTask, message);
}

extern(C)
int unitReadyHandler(nxt_unit_ctx_t* context)
{
    return NXT_UNIT_OK;
}

void logUnit(
    nxt_unit_ctx_t* unitContext,
    UnitLogLevel logLevel,
    string message
) @trusted nothrow
{
    try
        nxt_unit_log(
            unitContext,
            logLevel,
            ("[D] " ~ format("%s ", thisTid) ~ message).toStringz
        );
    catch(Exception e){};
}

enum UnitLogLevel : uint
{
    alert = NXT_UNIT_LOG_ALERT,
    error = NXT_UNIT_LOG_ERR,
    warn = NXT_UNIT_LOG_WARN,
    notice = NXT_UNIT_LOG_NOTICE,
    info = NXT_UNIT_LOG_INFO,
    debug_ = NXT_UNIT_LOG_DEBUG,
};