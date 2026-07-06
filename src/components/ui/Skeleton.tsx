import { cx } from '../../lib/cx'

/** Placeholder pulsante de carregamento (só tokens). */
export function Skeleton({ className }: { className?: string }) {
  return <div className={cx('animate-pulse rounded-md bg-bg-hover', className)} />
}
