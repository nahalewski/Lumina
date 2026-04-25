import sys
import json
import torch
from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

def translate(lines):
    model_name = "facebook/nllb-200-distilled-600M"
    
    # Use MPS if on Apple Silicon, else CPU
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    
    tokenizer = AutoTokenizer.from_pretrained(model_name, src_lang="jpn_Jpan")
    model = AutoModelForSeq2SeqLM.from_pretrained(model_name).to(device)

    # NLLB needs specific source/target language codes
    # Japanese is 'jpn_Jpan', English is 'eng_Latn'
    translated_lines = []
    
    # Process in small batches to avoid memory issues
    batch_size = 5
    for i in range(0, len(lines), batch_size):
        batch = lines[i:i+batch_size]
        
        # Report progress to stderr
        progress = (i + len(batch)) / len(lines)
        print(f"PROGRESS:{progress:.2f}", file=sys.stderr, flush=True)
        
        inputs = tokenizer(batch, return_tensors="pt", padding=True, truncation=True).to(device)
        
        translated_tokens = model.generate(
            **inputs, 
            forced_bos_token_id=tokenizer.convert_tokens_to_ids("eng_Latn"), 
            max_length=128
        )
        
        results = tokenizer.batch_decode(translated_tokens, skip_special_tokens=True)
        translated_lines.extend(results)
        
    return translated_lines

if __name__ == "__main__":
    try:
        # Read JSON from stdin
        input_data = sys.stdin.read()
        if not input_data:
            print(json.dumps([]))
            sys.exit(0)
            
        lines = json.loads(input_data)
        
        # Debug log
        with open("/Users/bennahalewski/Documents/SRT PLAYER/nllb_debug.log", "a") as f:
            f.write(f"INPUT: {json.dumps(lines)}\n")
            
        if not isinstance(lines, list):
            print(json.dumps({"error": "Input must be a JSON list"}))
            sys.exit(1)
            
        output = translate(lines)
        
        with open("/Users/bennahalewski/Documents/SRT PLAYER/nllb_debug.log", "a") as f:
            f.write(f"OUTPUT: {json.dumps(output)}\n")
            
        sys.stdout.write(json.dumps(output))
        sys.stdout.flush()
        sys.exit(0)
    except Exception as e:
        with open("/Users/bennahalewski/Documents/SRT PLAYER/nllb_debug.log", "a") as f:
            f.write(f"CRASH: {str(e)}\n")
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
