import * as React from 'react';
import * as PropTypes from 'prop-types';
import './Accordion.less';
import cnCreate from 'utils/cnCreate';
import Header from 'components/Header/Header';
import Collapse from 'components/Collapse/Collapse';
import ArrowUp from 'icons/System/24/Arrow_up_24.svg';
import ArrowDown from 'icons/System/24/Arrow_down_24.svg';

export interface IAccordionProps {
    /** Заголовок 10 */
    title: string;
    /** Состояние открытости */
    isOpened?: boolean;
    /** Дополнительные классы для внутренних элементов */
    classes?: {
        root?: string;
        collapse?: string;
    };
    /** Обработчик клика */
    onClickAccordion?: (isOpened: boolean, title: string) => void;
}

const cn = cnCreate('mfui-beta-accordion');
const Accordion: React.FC<IAccordionProps> = ({
    title,
    isOpened: isOpenedProps = false,
    classes: {
        root: rootPropsClasses = '',
        collapse: collapsePropsClasses = '',
    } = {},
    onClickAccordion,
    children,
}) => {
    const [isOpened, setIsOpened] = React.useState<boolean>(isOpenedProps);

    React.useEffect(() => {
        setIsOpened(isOpenedProps);
    }, [isOpenedProps]);

    const handleClickTitle = (): void => {
        onClickAccordion && onClickAccordion(!isOpened, title);

        setIsOpened(!isOpened);
    };

    return (
        <div className={cn({ open: isOpened }, rootPropsClasses)}>
            <div className={cn('title-wrap')} onClick={handleClickTitle}>
                <Header as="h5">{title}</Header>
                <div className={cn('icon-box', { open: isOpened })}>
                    {isOpened
                        ? (<ArrowUp />)
                        : (<ArrowDown />)
                    }
                </div>
            </div>
            <Collapse
                className={cn('content', collapsePropsClasses)}
                classNameContainer={cn('content-inner')}
                isOpened={isOpened}
            >
                {children}
            </Collapse>
        </div>
    );
};

Accordion.propTypes = {
    title: PropTypes.string.isRequired,
    isOpened: PropTypes.bool,
    classes: PropTypes.shape({
        root: PropTypes.string,
        collapse: PropTypes.string,
    }),
    onClickAccordion: PropTypes.func,
};

export default Accordion;
