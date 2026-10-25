{
  # halo's resident Strata model; two sessions at 256K each.
  # maxConcurrent 2 takes both slots; halo's assistant and interactive pi
  # queue behind dispatch workers.
  "lemonade/Qwen3.8-Flash-Next-Strata" = {
    baseUrl = "http://halo:13305/v1";
    contextWindow = 262144;
    # Thinking counts against pi's 16384 default output cap.
    maxTokens = 32768;
    # The BF16 mmproj loads apart from the quant, so this endpoint is
    # vision-capable; unset, pi registers it text-only and a worker's
    # screenshots never arrive.
    input = ["text" "image"];
    maxConcurrent = 2;
    tiers = ["trivial" "standard"];
    reasoning = true;
    thinkingFormat = "qwen-chat-template";
    effortThinking = {low = "off";};
  };
}
