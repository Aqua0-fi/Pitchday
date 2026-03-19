import { useQuery } from '@tanstack/react-query';
import { useWallet } from '@/contexts/wallet-context';

export interface UserPosition {
    positionId: string;
    poolId: string;
    tickLower: number;
    tickUpper: number;
    liquidityShares: string;
    active: boolean;
}

export function useUserPositions(chainId: number) {
    const { address } = useWallet();

    return useQuery({
        queryKey: ['v4UserPositions', chainId, address],
        queryFn: async () => {
            if (!address) return [];
            const res = await fetch(`/api/v1/v4/lp/positions/${address}?chainId=${chainId}`, {
                headers: {
                    'X-API-Key': 'Aqua0-gigachads',
                },
            });
            if (!res.ok) {
                console.error("Failed to fetch user positions");
                return [];
            }
            const data = await res.json();
            return (data.positions || []) as UserPosition[];
        },
        enabled: !!address && !!chainId,
    });
}
