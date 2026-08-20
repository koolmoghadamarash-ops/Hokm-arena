import { createTestServer, shutdownTestServer, mkClient, onceMessage } from "./helpers/testServer";
describe("HokmRoom integration", () => {
  let ctx: Awaited<ReturnType<typeof createTestServer>>;
  beforeAll(async () => { process.env.TURN_TIMEOUT_SECONDS="2"; ctx=await createTestServer(); });
  afterAll(async () => { await shutdownTestServer(ctx.httpServer, ctx.gameServer); });
  test("4 players reach trump selection", async () => {
    const c1=await mkClient(ctx.endpoint); const c2=await mkClient(ctx.endpoint);
    const c3=await mkClient(ctx.endpoint); const c4=await mkClient(ctx.endpoint);
    const r1=await c1.joinOrCreate("hokm",{userId:"u1"});
    const r2=await c2.joinOrCreate("hokm",{userId:"u2"});
    const r3=await c3.joinOrCreate("hokm",{userId:"u3"});
    const r4=await c4.joinOrCreate("hokm",{userId:"u4"});
    r1.send("player.ready"); r2.send("player.ready"); r3.send("player.ready"); r4.send("player.ready");
    const patch = await onceMessage<any>(r1, "state.patch");
    expect(patch.phase).toBe("TRUMP_SELECTION");
    await r1.leave(); await r2.leave(); await r3.leave(); await r4.leave();
  });
});
