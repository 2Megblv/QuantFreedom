import sys
files = [
    "MultiAssetEA_Pro2.0/Core/CSymbolManager.mqh",
    "MultiAssetEA_Pro2.0/Indicators/CIndicatorManager.mqh",
    "MultiAssetEA_Pro2.0/Core/CEngine.mqh",
    "MultiAssetEA_Pro2.0/Strategies/CVolatilityMomentum.mqh",
    "MultiAssetEA_Pro2.0/Indicators/QFisher_ARMI_TickVolume.mq5"
]

for f in files:
    text = open(f).read()
    in_single = False
    in_double = False
    stack = []
    for i, line in enumerate(text.split("\n")):
        in_single = False
        in_double = False
        skip_next = False
        for j, c in enumerate(line):
            if skip_next:
                skip_next = False
                continue
            if c == "\\" and j+1 < len(line):
                skip_next = True
                continue
            if c == "'" and not in_double:
                in_single = not in_single
            elif c == '"' and not in_single:
                in_double = not in_double
            elif c == "{" and not in_single and not in_double:
                stack.append(i+1)
            elif c == "}" and not in_single and not in_double:
                if not stack:
                    print(f"Extra }} at {f}:{i+1}")
                else:
                    stack.pop()
    if stack:
        print(f"Unclosed {{ at {f}:{stack}")
    else:
        print(f"{f} Braces OK")
