struct VSOut {
    float4 pos : SV_Position;
    uint layer : SV_RenderTargetArrayIndex;
};
VSOut main(uint vid : SV_VertexID, uint iid : SV_InstanceID) {
    float2 p[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
    VSOut o;
    o.pos = float4(p[vid], 0, 1);
    o.layer = iid;
    return o;
}
