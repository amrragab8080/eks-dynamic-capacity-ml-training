import os
import torch
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP
from torch.utils.data import DataLoader, DistributedSampler
from torchvision import datasets, transforms

def setup():
    dist.init_process_group(backend='nccl')
    local_rank = int(os.environ.get('LOCAL_RANK', '0'))
    if torch.cuda.is_available():
        torch.cuda.set_device(local_rank)

def cleanup():
    dist.destroy_process_group()

def train():
    setup()
    
    rank = dist.get_rank()
    world_size = dist.get_world_size()
    local_rank = int(os.environ.get('LOCAL_RANK', '0'))
    
    print(f"Rank {rank}/{world_size} on GPU {local_rank if torch.cuda.is_available() else 'CPU'}")
    
    # Simple model
    device = torch.device(f'cuda:{local_rank}' if torch.cuda.is_available() else 'cpu')
    model = torch.nn.Sequential(
        torch.nn.Linear(784, 128),
        torch.nn.ReLU(),
        torch.nn.Linear(128, 10)
    ).to(device)
    
    model = DDP(model, device_ids=[local_rank] if torch.cuda.is_available() else None)
    
    # Dataset
    transform = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize((0.1307,), (0.3081,))
    ])
    
    dataset = datasets.MNIST('/data', train=True, download=True, transform=transform)
    sampler = DistributedSampler(dataset, num_replicas=world_size, rank=rank)
    loader = DataLoader(dataset, batch_size=64, sampler=sampler)
    
    optimizer = torch.optim.Adam(model.parameters(), lr=0.001)
    criterion = torch.nn.CrossEntropyLoss()
    
    # Training loop
    for epoch in range(5):
        sampler.set_epoch(epoch)
        for batch_idx, (data, target) in enumerate(loader):
            data = data.view(-1, 784).to(device)
            target = target.to(device)
            
            optimizer.zero_grad()
            output = model(data)
            loss = criterion(output, target)
            loss.backward()
            optimizer.step()
            
            if batch_idx % 100 == 0 and rank == 0:
                print(f"Epoch {epoch} Batch {batch_idx} Loss {loss.item():.4f}")
    
    if rank == 0:
        print("Training complete!")
    
    cleanup()

if __name__ == "__main__":
    train()
